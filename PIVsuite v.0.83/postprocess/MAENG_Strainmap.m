function eff = MAENG_Strainmap(pivData)
% MAENG_Strainmap — 정방향(Forward) Pathline 적분 누적 유효변형률 맵 + 유맥선(Streakline)
% ============================================================================
%  [1] 총 유효변형률 맵 (Fig.3 흐름도)
%      du_i (=pivData.U,V) → dε_ij = ½(∂du_i/∂x_j+∂du_j/∂x_i)
%                          → dε̄ = √(2/3·dε_ij·dε_ij)
%                          → ε̄ = Σ_pathline dε̄
%      · 정방향 추적: 시드(START_FRAME 격자)→시간 순방향 이류, 경로 따라 dε̄ 누적
%      · 결과는 시드 격자(기준 형상)에 1:1 복귀 → scatter 보간 없이 빈틈없는 필드
%      · 좌표: mm
%
%  [2] 유맥선(Streakline)  ★ 내가 긋는 직선을 n등분하여 주입
%      · 연속 주입식: 매 프레임 각 주입점에서 새 입자 방출, 전체 입자 순방향 이류
%      · 입자별 Coast Limit(연속 NaN 관성 돌파 후 정지)로 마스크/장애물 처리
%      · 좌표: 픽셀(기존 MAENG_Streaklines.m 컨벤션) + 프레임별 배경 애니메이션
%
%  실행: 인자 없이 F5 (워크스페이스 pivData 자동 로드) 또는 eff = MAENG_Strainmap(pivData)
% ============================================================================

  %% ==========================================================
  %% ⚙️ 사용자 설정 — 변형률 맵
  %% ==========================================================
  dt      = 0.001;    % 시간 간격 [s] (총 변형률엔 미사용, 메타 저장용)
  mmPerPx = 0.00468;  % [mm/px] (총 변형률엔 영향 없음: 비율로 상쇄)
  VIS_TRANSPARENCY = 0.7;     % 1차 오버레이 투명도
  VIS_COLORMAP     = 'turbo'; % 색상 맵

  START_FRAME  = [700];   % 적분 시작 프레임 (빈 값 = 1)        ← 시드 위치/기준 형상
  TARGET_FRAME = [];   % 적분 종료 프레임 (빈 값 = 마지막 프레임)
  ROI_LIMITS   = [];   % [xmin xmax ymin ymax] mm, 빈 값 = 전체

  %% ==========================================================
  %% 🌊 사용자 설정 — 스트릭라인(Streakline)
  %% ==========================================================
  DO_STREAKLINE   = true;   % 스트릭라인 플롯 on/off
  N_STREAK        = 12;     % ★ 내가 긋는 직선을 몇 개로 등분할지(주입점 개수)
  STREAK_COASTMAX = 3;      % 연속 NaN 관성 돌파 한계 [frames] → 초과 시 정지
  STREAK_PAUSE    = 0.03;   % 애니메이션 프레임 지연 [s]
  STREAK_LW       = 1.5;    % 스트릭라인 두께

  %% ==========================================================
  %% 📥 pivData 자동 로드 (인자 없이 F5 실행 지원)
  %% ==========================================================
  if nargin < 1 || isempty(pivData)
      if evalin('base','exist(''pivData'',''var'')')
          pivData = evalin('base','pivData');
          fprintf('[자동 로드] 워크스페이스의 pivData 사용\n');
      else
          [f,p] = uigetfile('*.mat','pivData가 저장된 .mat 선택');
          if isequal(f,0), disp('취소됨.'); eff = []; return; end
          S = load(fullfile(p,f)); fn = fieldnames(S); pivData = S.(fn{1});
      end
  end

  %% ==========================================================
  %% 📐 데이터 크기 및 프레임 설정
  %% ==========================================================
  if ndims(pivData.U) < 3
      warning('pivData.U가 3차원(시퀀스)이 아닙니다. 단일 프레임만 계산됩니다.');
      Nt = 1;
  else
      Nt = size(pivData.U, 3);
  end

  if isempty(START_FRAME)  || START_FRAME  < 1 || START_FRAME  > Nt, START_FRAME  = 1;  end
  if isempty(TARGET_FRAME) || TARGET_FRAME < 1 || TARGET_FRAME > Nt, TARGET_FRAME = Nt; end
  if TARGET_FRAME < START_FRAME
      warning('TARGET_FRAME < START_FRAME → 두 값을 교환합니다.');
      tmp = START_FRAME; START_FRAME = TARGET_FRAME; TARGET_FRAME = tmp;
  end

  X_mm = double(pivData.X) * mmPerPx;
  Y_mm = double(pivData.Y) * mmPerPx;
  dx = double(pivData.iaStepX) * mmPerPx;
  dy = double(pivData.iaStepY) * mmPerPx;

  %% ==========================================================
  %% 🌱 시드 생성: START_FRAME 격자점 (ROI 내부)
  %% ==========================================================
  if ~isempty(ROI_LIMITS)
      roi_mask = (X_mm >= ROI_LIMITS(1) & X_mm <= ROI_LIMITS(2)) & ...
                 (Y_mm >= ROI_LIMITS(3) & Y_mm <= ROI_LIMITS(4));
  else
      roi_mask = true(size(X_mm));
  end
  Px_start = X_mm(roi_mask);
  Py_start = Y_mm(roi_mask);

  Px = Px_start;
  Py = Py_start;
  Eps_accum_1D = zeros(size(Px));

  fprintf('정방향 Pathline 추적: 프레임 %d → %d, 시드 %d개\n', ...
          START_FRAME, TARGET_FRAME, numel(Px));

  %% ==========================================================
  %% 🚀 Forward Lagrangian Tracking + dε̄ 적분
  %% ==========================================================
  for k = START_FRAME : TARGET_FRAME
      Uk_orig = double(pivData.U(:,:,k)) * mmPerPx;
      Vk_orig = double(pivData.V(:,:,k)) * mmPerPx;

      isMasked = isnan(Uk_orig);
      Uk_orig(isMasked) = NaN;
      Vk_orig(isMasked) = NaN;

      [dUdx, dUdy] = robust_nan_gradient(Uk_orig, dx, dy);
      [dVdx, dVdy] = robust_nan_gradient(Vk_orig, dx, dy);
      deps_xx = dUdx;
      deps_yy = dVdy;
      deps_xy = 0.5 * (dUdy + dVdx);
      deps_eff = sqrt((2/3) * (deps_xx.^2 + deps_yy.^2 + 2*deps_xy.^2));

      deps_p = interp2(X_mm, Y_mm, deps_eff, Px, Py, 'linear', NaN);
      valid_idx = ~isnan(deps_p);
      Eps_accum_1D(valid_idx) = Eps_accum_1D(valid_idx) + deps_p(valid_idx);

      if k == TARGET_FRAME, break; end

      U_filled = inpaint_nans(Uk_orig, 4);
      V_filled = inpaint_nans(Vk_orig, 4);

      Up_filled = interp2(X_mm, Y_mm, U_filled, Px, Py, 'linear', 0);
      Vp_filled = interp2(X_mm, Y_mm, V_filled, Px, Py, 'linear', 0);

      % ★ 정방향 1프레임 이류
      Px_new = Px + Up_filled;
      Py_new = Py + Vp_filled;

      dest_check = interp2(X_mm, Y_mm, Uk_orig, Px_new, Py_new, 'nearest', NaN);
      hit_mask = isnan(dest_check) & ~isnan(Px);
      hit_idx  = find(hit_mask);
      num_hits = numel(hit_idx);

      if num_hits > 0
          speed    = sqrt(Up_filled(hit_idx).^2 + Vp_filled(hit_idx).^2);
          ang_orig = atan2(Vp_filled(hit_idx), Up_filled(hit_idx));   % ★ 정방향 진행각
          angles   = [5,-5,15,-15,30,-30,45,-45,60,-60,75,-75,89,-89] * (pi/180);

          Px_curr = Px(hit_idx);  Py_curr = Py(hit_idx);
          Px_resolved = Px_curr;  Py_resolved = Py_curr;
          resolved_mask = false(num_hits, 1);

          for ang_offset = angles
              if all(resolved_mask), break; end
              unresolved = ~resolved_mask;
              ang_test = ang_orig(unresolved) + ang_offset;

              vx_test = cos(ang_test) .* speed(unresolved);
              vy_test = sin(ang_test) .* speed(unresolved);

              x_test = Px_curr(unresolved) + vx_test;   % ★ 정방향 + 회전
              y_test = Py_curr(unresolved) + vy_test;

              test_valid = ~isnan(interp2(X_mm, Y_mm, Uk_orig, x_test, y_test, 'nearest', NaN));

              idx_unresolved_global = find(unresolved);
              valid_global = idx_unresolved_global(test_valid);

              Px_resolved(valid_global) = x_test(test_valid);
              Py_resolved(valid_global) = y_test(test_valid);
              resolved_mask(valid_global) = true;
          end
          Px_new(hit_idx) = Px_resolved;
          Py_new(hit_idx) = Py_resolved;
      end

      Px = Px_new;
      Py = Py_new;
  end
  fprintf('적분 완료!\n');

  %% ==========================================================
  %% 🗺️ 1D 누적값 → 2D 필드 (시드 격자 = START_FRAME 기준 형상)
  %% ==========================================================
  Eps_accum_2D = nan(size(X_mm));
  Eps_accum_2D(roi_mask) = Eps_accum_1D;

  true_mask = true(size(X_mm));
  for k = 1:Nt
      Uk_test = double(pivData.U(:,:,k));
      Vk_test = double(pivData.V(:,:,k));
      true_mask = true_mask & ((Uk_test == 0 & Vk_test == 0) | isnan(Uk_test));
  end
  Eps_accum_2D(true_mask) = NaN;

  eff.direction     = 'forward';
  eff.dt            = dt;
  eff.mmPerPx       = mmPerPx;
  eff.startFrame    = START_FRAME;
  eff.targetFrame   = TARGET_FRAME;
  eff.roiLimits     = ROI_LIMITS;
  eff.eps_eff_accum = Eps_accum_2D;
  eff.X_mm          = X_mm;
  eff.Y_mm          = Y_mm;

  %% ==========================================================
  %% 🖼️ 배경 이미지(기준 형상): START_FRAME 이미지
  %% ==========================================================
  bg_img = load_bg_image(pivData, START_FRAME);
  x_world = [min(X_mm(:)) - dx/2, max(X_mm(:)) + dx/2];
  y_world = [min(Y_mm(:)) - dy/2, max(Y_mm(:)) + dy/2];

  %% ==========================================================
  %% 🎨 1차 시각화: 전체 영역 변형률 맵
  %% ==========================================================
  fig_main = figure('Name', sprintf('Forward Accumulated Strain (Frame %d→%d)', ...
                    START_FRAME, TARGET_FRAME), 'Color', 'w');
  if ~isempty(bg_img), image(x_world, y_world, bg_img); end
  set(gca, 'YDir', 'reverse'); hold on;

  [~, hContour] = contourf(X_mm, Y_mm, Eps_accum_2D, 100, 'LineStyle', 'none');
  alpha(hContour, VIS_TRANSPARENCY);

  axis equal tight; box on;
  colormap(VIS_COLORMAP);
  cb = colorbar;
  ylabel(cb, 'Accumulated Effective Strain $\bar{\epsilon}$ [-]', ...
         'FontSize', 12, 'Interpreter', 'latex');
  xlabel('x [mm]', 'FontSize', 12); ylabel('y [mm]', 'FontSize', 12);
  title(sprintf('정방향 누적 변형률 (Frame %d→%d, 기준 형상)', ...
        START_FRAME, TARGET_FRAME), 'FontSize', 14, 'Interpreter', 'none');
  hold off;

  %% ==========================================================
  %% 🖱️ 2차 시각화: ROI 선택 후 불투명 렌더링
  %% ==========================================================
  disp('>> 1차 전체 영역 변형률 맵 생성 완료.');
  disp('>> 렌더링을 유지할 관심 영역(사각형)을 마우스로 드래그하세요...');

  figure(fig_main);
  rect = getrect(fig_main);
  dispROI = [rect(1), rect(1)+rect(3), rect(2), rect(2)+rect(4)];

  roi_mask_disp = (X_mm >= dispROI(1) & X_mm <= dispROI(2)) & ...
                  (Y_mm >= dispROI(3) & Y_mm <= dispROI(4));
  Eps_accum_final = Eps_accum_2D;
  Eps_accum_final(~roi_mask_disp) = NaN;

  figure('Name', 'Final ROI Strain Field (Forward, Opacity 1.0)', 'Color', 'w');
  if ~isempty(bg_img), image(x_world, y_world, bg_img); end
  set(gca, 'YDir', 'reverse'); hold on;

  [~, hContour_final] = contourf(X_mm, Y_mm, Eps_accum_final, 100, 'LineStyle', 'none');
  alpha(hContour_final, 1.0);

  axis([min(x_world) max(x_world) min(y_world) max(y_world)]); axis equal;
  box on; colormap(VIS_COLORMAP);
  cb2 = colorbar;
  ylabel(cb2, 'Accumulated Effective Strain $\bar{\epsilon}$ [-]', ...
         'FontSize', 12, 'Interpreter', 'latex');
  xlabel('x [mm]', 'FontSize', 12); ylabel('y [mm]', 'FontSize', 12);
  title('잘라낸 영역 변형률 필드 (Forward, Opacity 1.0)', ...
        'FontSize', 14, 'Interpreter', 'none');
  hold off;
  disp('>> 변형률 맵 2차 렌더링 완료.');

  %% ==========================================================
  %% 🌊 유맥선(Streakline) — 내가 긋는 직선 n등분 연속 주입
  %% ==========================================================
  if DO_STREAKLINE
      Xpx = double(pivData.X);    % 픽셀 격자 (스트릭라인은 픽셀 기준)
      Ypx = double(pivData.Y);
      minXp = min(Xpx(:)); maxXp = max(Xpx(:));
      minYp = min(Ypx(:)); maxYp = max(Ypx(:));

      bg0 = load_bg_image(pivData, START_FRAME);   % 시드/초기 배경(RGB)
      fileList = build_file_list(pivData);         % 프레임별 배경(애니메이션)

      if isempty(bg0)
          warning('스트릭라인용 배경 이미지를 찾지 못해 스트릭라인을 건너뜁니다.');
      else
          if isfield(pivData,'imSizeX'), imSizeX = pivData.imSizeX; else, imSizeX = size(bg0,2); end
          if isfield(pivData,'imSizeY'), imSizeY = pivData.imSizeY; else, imSizeY = size(bg0,1); end

          % --- 직선 2점 클릭 → n등분 주입점 ---
          disp('>> [스트릭라인] 주입선을 그릴 두 점을 클릭하세요...');
          hSeed = figure('Name','Streakline 주입선 설정','NumberTitle','off','Color','w');
          imshow(bg0, 'InitialMagnification','fit'); hold on;
          title(sprintf('주입선을 그릴 두 점을 클릭 (직선을 %d등분)', N_STREAK), 'FontSize',13);
          [xL, yL] = ginput(2);
          plot(xL, yL, 'y-', 'LineWidth', 2);
          plot(xL, yL, 'ys', 'MarkerFaceColor','y', 'MarkerSize', 8);

          xs = linspace(xL(1), xL(2), N_STREAK).';   % ★ 직선 등분 주입점
          ys = linspace(yL(1), yL(2), N_STREAK).';
          plot(xs, ys, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 4);
          title(sprintf('주입점 %d개 균등 분포', N_STREAK), 'FontSize',13);
          pause(0.7); close(hSeed);

          % 경계 클램프 (속도 격자 밖 시드 보정)
          xs = max(min(xs, maxXp), minXp);
          ys = max(min(ys, maxYp), minYp);

          % --- 연속 주입식 추적 변수 ([주입점 x 프레임]) ---
          Nf = TARGET_FRAME - START_FRAME + 1;
          posX = nan(N_STREAK, Nf);  posY = nan(N_STREAK, Nf);
          prev_u = zeros(N_STREAK, Nf);  prev_v = zeros(N_STREAK, Nf);
          coast  = zeros(N_STREAK, Nf);   % 입자별 연속 NaN 카운트

          % --- 시각화 준비 ---
          hFig = figure('Name','Streakline (직선 n등분 주입)','Color','w','Renderer','opengl');
          ax = axes('Parent', hFig); hold(ax, 'on');
          set(ax, 'YDir','reverse', 'XDir','normal', 'DataAspectRatio',[1 1 1]);
          hIm = imshow(bg0, 'Parent', ax, 'XData',[1 imSizeX], 'YData',[1 imSizeY]);

          cols = lines(N_STREAK);
          hL = gobjects(N_STREAK,1);  hP = gobjects(N_STREAK,1);
          for i = 1:N_STREAK
              hL(i) = plot(ax, NaN, NaN, '-', 'Color', cols(i,:), 'LineWidth', STREAK_LW);
              hP(i) = plot(ax, NaN, NaN, '.', 'Color', cols(i,:), 'MarkerSize', 8);
          end

          % --- 연속 주입 + 이류 (Coast Limit) ---
          for fi = 1:Nf
              t = START_FRAME + fi - 1;

              % 배경 업데이트
              if ~isempty(fileList) && t <= numel(fileList)
                  try, set(hIm, 'CData', imread(fileList{t})); catch, end
              end

              % 새 입자 주입 (현재 프레임)
              posX(:, fi) = xs;  posY(:, fi) = ys;

              % 활성 입자(주입시각 1:fi) 선/점 갱신
              for i = 1:N_STREAK
                  set(hL(i), 'XData', posX(i, 1:fi), 'YData', posY(i, 1:fi));
                  set(hP(i), 'XData', posX(i, 1:fi), 'YData', posY(i, 1:fi));
              end
              title(ax, sprintf('Streakline  Frame %d / %d', t, TARGET_FRAME), 'FontSize',13);
              drawnow; pause(STREAK_PAUSE);

              if fi == Nf, break; end

              % 지금까지 주입된 모든 입자 이류 (주입시각 p = 1:fi)
              Ut = double(pivData.U(:,:,t));
              Vt = double(pivData.V(:,:,t));
              for p = 1:fi
                  xc = posX(:, p);  yc = posY(:, p);   % N_STREAK 벡터 (i에 대해 벡터화)
                  uv = interp2(Xpx, Ypx, Ut, xc, yc, 'nearest');
                  vv = interp2(Xpx, Ypx, Vt, xc, yc, 'nearest');

                  bad  = isnan(uv) | isnan(vv);
                  good = ~bad;

                  % NaN 입자: 관성 돌파 카운트 증가
                  coast(bad, p) = coast(bad, p) + 1;

                  uv_use = uv;  vv_use = vv;
                  % 관성 유지(한계 이내): 직전 정상 속도 사용 (prev 미갱신 → 관성 지속)
                  stillCoast = bad & (coast(:,p) <= STREAK_COASTMAX);
                  uv_use(stillCoast) = prev_u(stillCoast, p);
                  vv_use(stillCoast) = prev_v(stillCoast, p);
                  % 한계 초과: 장애물/경계로 완전 정지
                  stopped = bad & (coast(:,p) > STREAK_COASTMAX);
                  uv_use(stopped) = 0;  vv_use(stopped) = 0;
                  prev_u(stopped, p) = 0;  prev_v(stopped, p) = 0;
                  % 정상 영역: 카운트 초기화 + 속도 갱신
                  coast(good, p) = 0;
                  prev_u(good, p) = uv(good);  prev_v(good, p) = vv(good);

                  xn = xc + uv_use;  yn = yc + vv_use;
                  posX(:, p) = max(min(xn, maxXp), minXp);
                  posY(:, p) = max(min(yn, maxYp), minYp);
              end
          end
          title(ax, sprintf('Streakline 완료 (주입점 %d개, Frame %d→%d)', ...
                N_STREAK, START_FRAME, TARGET_FRAME), 'FontSize',13);
          hold(ax, 'off');

          eff.streak.seedX  = xs;
          eff.streak.seedY  = ys;
          eff.streak.posX   = posX;
          eff.streak.posY   = posY;
          eff.streak.frames = [START_FRAME, TARGET_FRAME];
          disp('>> 스트릭라인 생성 완료.');
      end
  end

end

%% ============================================================
%% 🛠 로컬 함수 1: 결측치 인지형 편측 미분 (NaN-Aware Gradient)
%% ============================================================
function [dFdx, dFdy] = robust_nan_gradient(F, dx, dy)
    [Ny, Nx] = size(F);
    dFdx = nan(Ny, Nx);
    dFdy = nan(Ny, Nx);
    for i = 1:Ny
        for j = 1:Nx
            if isnan(F(i,j)), continue; end

            has_left  = (j > 1)  && ~isnan(F(i, j-1));
            has_right = (j < Nx) && ~isnan(F(i, j+1));
            if has_left && has_right
                dFdx(i,j) = (F(i, j+1) - F(i, j-1)) / (2 * dx);
            elseif has_left && ~has_right
                dFdx(i,j) = (F(i, j) - F(i, j-1)) / dx;
            elseif ~has_left && has_right
                dFdx(i,j) = (F(i, j+1) - F(i, j)) / dx;
            end

            has_up   = (i > 1)  && ~isnan(F(i-1, j));
            has_down = (i < Ny) && ~isnan(F(i+1, j));
            if has_up && has_down
                dFdy(i,j) = (F(i+1, j) - F(i-1, j)) / (2 * dy);
            elseif has_up && ~has_down
                dFdy(i,j) = (F(i, j) - F(i-1, j)) / dy;
            elseif ~has_up && has_down
                dFdy(i,j) = (F(i+1, j) - F(i, j)) / dy;
            end
        end
    end
end

%% ============================================================
%% 🛠 로컬 함수 2: 배경 이미지 로더 (imFilename1 우선, cell/char 대응)
%% ============================================================
function bg = load_bg_image(pivData, frameIdx)
    bg = [];
    cand = {};
    if isfield(pivData, 'imFilename1'), cand{end+1} = pivData.imFilename1; end
    if isfield(pivData, 'imFilename2'), cand{end+1} = pivData.imFilename2; end
    for c = 1:numel(cand)
        fn = cand{c};
        if iscell(fn)
            idx = min(frameIdx, numel(fn));
            fn = fn{idx};
        end
        if (ischar(fn) || isstring(fn)) && exist(fn, 'file')
            try
                bg = imread(fn);
                if size(bg,3) == 1, bg = cat(3, bg, bg, bg); end
                return;
            catch
            end
        end
    end
end

%% ============================================================
%% 🛠 로컬 함수 3: 프레임별 배경 fileList 구성 (애니메이션용)
%%    우선순위: base fileList → imFilename1/2(cell) → imagePath 스캔
%% ============================================================
function fileList = build_file_list(pivData)
    fileList = {};
    % 1) base workspace fileList
    try
        if evalin('base','exist(''fileList'',''var'')')
            fileList = evalin('base','fileList');
            if ~isempty(fileList), return; end
        end
    catch
    end
    % 2) imFilename1 / imFilename2 (cell 배열)
    for fld = {'imFilename1','imFilename2'}
        f = fld{1};
        if isfield(pivData, f) && iscell(pivData.(f)) && ~isempty(pivData.(f))
            fileList = pivData.(f);
            return;
        end
    end
    % 3) imagePath 폴더 스캔
    if isfield(pivData,'imagePath') && exist(pivData.imagePath,'dir')
        D = dir(fullfile(pivData.imagePath,'*.png'));
        if isempty(D), D = dir(fullfile(pivData.imagePath,'*.bmp')); end
        if isempty(D), D = dir(fullfile(pivData.imagePath,'*.tif')); end
        if ~isempty(D)
            [~,idx] = sort({D.name});
            fileList = fullfile(pivData.imagePath, {D(idx).name});
        end
    end
    % 4) 없으면 빈 cell → 호출부에서 정적 배경 사용
end