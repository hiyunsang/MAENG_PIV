function eff = pivEffStrain(pivData)
% pivEffStrain — Lagrangian 누적 유효 변형률(Effective Strain) 계산 · 시각화 · 애니메이션
%
%   ▶ F5(실행)만 눌러도 동작: 작업공간의 pivData 자동 로드 → 없으면 .mat 파일 선택
%
%   [요청 반영]
%     1) 실행(Run/F5)만으로 동작        — pivData 자동 로드 + 파일 선택 폴백
%     2) inputdlg 로 시작/끝 프레임 지정 — 미입력 시 1 ~ 끝(Nt)
%     3) 컬러바를 참고 사진과 동일하게   — turbo, 0~6, ε_eff (프레임 간 색 스케일 고정)
%     4) 변형률 누적 과정을 애니메이션으로 — 화면 재생 / MP4 저장 여부 선택
%
%   * 누적은 항상 1프레임부터 적분(=참고 사진처럼 t0 시점에도 누적값 존재).
%     start~end 는 "표시 구간"이며, 영상은 표시 프레임마다 1번까지 역추적함.

  %% ==========================================================
  %% ⚙️ 사용자 설정 (User Settings)
  %% ==========================================================
  dt        = 0.0005;     % 프레임 간 시간 간격 [s] (변형률 크기에는 무관, 기록용)
  mmPerPx   = 0.00234;    % 1픽셀당 물리 길이 [mm/px]

  STRAIN_CLIM      = [0 12];     % ★ 컬러바 범위 (참고 사진과 동일)
  VIS_COLORMAP     = 'turbo';   % 컬러맵
  VIS_TRANSPARENCY = 0.7;       % 오버레이 투명도 (배경 이미지가 비치도록)
  CONTOUR_LEVELS   = 80;        % 채움 등고선 단계 수 (부드러운 그라데이션)
  VIDEO_FPS        = 15;        % 출력 영상 프레임레이트
  VIDEO_MAX_FRAMES = 150;       % 영상 기본 표시 프레임 수 상한 (자동 step 계산용)

  %% ==========================================================
  %% 1) pivData 로드 — 실행만으로 동작
  %% ==========================================================
  if nargin < 1 || isempty(pivData)
      if evalin('base', 'exist(''pivData'',''var'')')
          pivData = evalin('base', 'pivData');          % 작업공간 자동 로드
          disp('>> 작업공간(base)의 pivData 를 불러왔습니다.');
      else
          [f, p] = uigetfile('*.mat', 'pivData 가 저장된 .mat 파일을 선택하세요');
          if isequal(f, 0), error('pivData 가 필요합니다. 실행을 취소합니다.'); end
          S = load(fullfile(p, f));
          if isfield(S, 'pivData'), pivData = S.pivData;
          else, fn = fieldnames(S); pivData = S.(fn{1}); end   % 첫 변수 사용
          fprintf('>> 파일에서 pivData 를 불러왔습니다: %s\n', f);
      end
  end

  %% ==========================================================
  %% 2) 차원 확인 및 물리 그리드 생성
  %% ==========================================================
  if ndims(pivData.U) < 3
      [Ny, Nx] = size(pivData.U); Nt = 1;
      warning('pivData.U 가 3차원(시퀀스)이 아닙니다. 단일 프레임으로 처리합니다.');
  else
      [Ny, Nx, Nt] = size(pivData.U);
  end

  X_mm = double(pivData.X) * mmPerPx;
  Y_mm = double(pivData.Y) * mmPerPx;
  dx   = double(pivData.iaStepX) * mmPerPx;
  dy   = double(pivData.iaStepY) * mmPerPx;

  x_world = [min(X_mm(:)) - dx/2, max(X_mm(:)) + dx/2];   % 배경 이미지 좌표 범위
  y_world = [min(Y_mm(:)) - dy/2, max(Y_mm(:)) + dy/2];

  %% ==========================================================
  %% 3) 표시 프레임 구간 입력 (미입력/취소 시 1 ~ Nt)
  %% ==========================================================
  prompt     = {'시작 프레임:', sprintf('종료 프레임 (최대 %d):', Nt)};
  ans_dialog = inputdlg(prompt, '표시 프레임 구간 설정', 1, {'1', num2str(Nt)});
  if isempty(ans_dialog)
      start_frame = 1; end_frame = Nt;                   % 취소 → 전체 구간
  else
      start_frame = round(str2double(ans_dialog{1}));
      end_frame   = round(str2double(ans_dialog{2}));
      if isnan(start_frame) || start_frame < 1, start_frame = 1;  end
      if isnan(end_frame)   || end_frame   > Nt, end_frame   = Nt; end
      if start_frame > end_frame
          [start_frame, end_frame] = deal(end_frame, start_frame);
      end
  end
  fprintf('>> 표시 구간: 프레임 %d ~ %d (누적은 항상 1프레임부터)\n', start_frame, end_frame);

  %% ==========================================================
  %% 4) 사전 계산: 영구 마스크 · 배경 파일 목록 · 정적(end_frame) 변형률
  %% ==========================================================
  trueMask = local_computePermanentMask(pivData, Ny, Nx, Nt);  % 공구 등 영구 마스크 (1회만)
  fileList = local_buildFileList(pivData, Nt);                 % 배경 이미지 목록 (1회만)

  fprintf('>> 정적 변형률 맵 계산 (Frame 1 → %d)...\n', end_frame);
  Eps_end = local_computeAccumStrain(pivData, end_frame, mmPerPx, X_mm, Y_mm, dx, dy, trueMask);

  % 결과 구조체 (그림을 닫아도 반환되도록 먼저 구성)
  eff.dt            = dt;
  eff.mmPerPx       = mmPerPx;
  eff.startFrame    = start_frame;
  eff.endFrame      = end_frame;
  eff.clim          = STRAIN_CLIM;
  eff.eps_eff_accum = Eps_end;     % end_frame 기준 2D 누적 유효 변형률
  eff.X_mm          = X_mm;
  eff.Y_mm          = Y_mm;

  %% ==========================================================
  %% 🎨 정적 시각화: end_frame 누적 변형률 맵
  %% ==========================================================
  fig1 = figure('Name', sprintf('Accumulated Strain (Frame 1 -> %d)', end_frame), 'Color', 'w');
  ax1  = axes('Parent', fig1);
  bg1  = local_loadBgImage(fileList, end_frame);

  local_drawStrain(ax1, bg1, X_mm, Y_mm, Eps_end, x_world, y_world, ...
                   CONTOUR_LEVELS, VIS_TRANSPARENCY, VIS_COLORMAP, STRAIN_CLIM);
  axis(ax1, 'tight');
  cb1 = colorbar(ax1); local_styleColorbar(cb1, STRAIN_CLIM);
  xlabel(ax1, 'x [mm]', 'FontSize', 12);
  ylabel(ax1, 'y [mm]', 'FontSize', 12);
  title(ax1, sprintf('누적 유효 변형률  (Frame 1 \\rightarrow %d)', end_frame), 'FontSize', 13);

  %% ==========================================================
  %% 🖱️ (선택) 관심 영역(ROI) 잘라내어 별도 표시
  %% ==========================================================
  if strcmp(questdlg('관심 영역(ROI)을 잘라내어 별도로 표시할까요?', ...
                     'ROI Crop', '예', '아니오', '아니오'), '예')
      figure(fig1);
      disp('>> fig1 화면에서 사각형 영역을 마우스로 드래그하세요...');
      rect  = getrect(fig1);
      dROI  = [rect(1), rect(1)+rect(3), rect(2), rect(2)+rect(4)];
      mROI  = (X_mm >= dROI(1) & X_mm <= dROI(2)) & (Y_mm >= dROI(3) & Y_mm <= dROI(4));
      Ecrop = Eps_end; Ecrop(~mROI) = NaN;

      fig2 = figure('Name', 'ROI Strain Field', 'Color', 'w');
      ax2  = axes('Parent', fig2);
      local_drawStrain(ax2, bg1, X_mm, Y_mm, Ecrop, x_world, y_world, ...
                       CONTOUR_LEVELS, 1.0, VIS_COLORMAP, STRAIN_CLIM);   % 잘라낸 영역은 불투명
      xlim(ax2, x_world); ylim(ax2, y_world);
      cb2 = colorbar(ax2); local_styleColorbar(cb2, STRAIN_CLIM);
      xlabel(ax2, 'x [mm]'); ylabel(ax2, 'y [mm]');
      title(ax2, '잘라낸 영역 변형률 필드');
  end

  %% ==========================================================
  %% 🎬 누적 변형률 애니메이션 (화면 재생 / MP4 저장)
  %% ==========================================================
  if strcmp(questdlg('변형률 누적 과정을 애니메이션으로 보시겠습니까?', ...
                     '애니메이션', '예', '아니오', '예'), '예')

      doSave = strcmp(questdlg('애니메이션을 MP4 파일로 저장할까요?  (아니오 = 화면 재생만)', ...
                               '영상 저장', '예', '아니오', '아니오'), '예');
      vw = []; savePath = '';
      if doSave
          [vf, vp] = uiputfile('*.mp4', 'MP4 저장 위치/이름', 'strain_animation.mp4');
          if isequal(vf, 0)
              doSave = false; disp('>> 저장 취소 → 화면 재생만 진행합니다.');
          else
              savePath = fullfile(vp, vf);
              vw = VideoWriter(savePath, 'MPEG-4');
              vw.Quality = 100; vw.FrameRate = VIDEO_FPS; open(vw);
          end
      end

      % 표시 프레임 자동 솎기 (상한 VIDEO_MAX_FRAMES) — O(N^2) 부담 완화
      span   = end_frame - start_frame + 1;
      step   = max(1, ceil(span / VIDEO_MAX_FRAMES));
      frames = start_frame:step:end_frame;
      nF     = numel(frames);
      fprintf('>> 애니메이션 렌더링: 프레임 %d~%d, step=%d, 총 %d장\n', ...
              start_frame, end_frame, step, nF);
      if span > 400
          warning(['표시 구간이 큽니다. 각 프레임마다 1번 프레임까지 역추적하므로 ', ...
                   '시간이 걸릴 수 있습니다.']);
      end

      figV = figure('Name', 'Accumulated Effective Strain — Animation', ...
                    'Color', 'w', 'Position', [120 120 900 650]);
      axV  = axes('Parent', figV);
      hWB  = waitbar(0, '변형률 누적 영상 생성 중...');
      refSize = [];   % 저장 프레임 크기 일관성 기준

      for ii = 1:nF
          k  = frames(ii);
          Ek = local_computeAccumStrain(pivData, k, mmPerPx, X_mm, Y_mm, dx, dy, trueMask);
          bg = local_loadBgImage(fileList, k);

          local_drawStrain(axV, bg, X_mm, Y_mm, Ek, x_world, y_world, ...
                           CONTOUR_LEVELS, VIS_TRANSPARENCY, VIS_COLORMAP, STRAIN_CLIM);
          xlim(axV, x_world); ylim(axV, y_world);
          cbV = colorbar(axV); local_styleColorbar(cbV, STRAIN_CLIM);
          xlabel(axV, 'x [mm]'); ylabel(axV, 'y [mm]');
          title(axV, sprintf('Accumulated \\epsilon_{eff}   (Frame %d / %d)', k, end_frame), ...
                'FontSize', 13);
          drawnow;

          if doSave && ~isempty(vw)
              frm = print(figV, '-RGBImage', '-r150');          % 모니터 독립 캡처
              hh = size(frm,1); ww = size(frm,2);
              frm = frm(1:hh-mod(hh,2), 1:ww-mod(ww,2), :);     % 코덱용 짝수 크기 보정
              if isempty(refSize)
                  refSize = [size(frm,1) size(frm,2)];
              elseif ~isequal([size(frm,1) size(frm,2)], refSize)
                  frm = imresize(frm, refSize);                 % 프레임 크기 일관성 유지
              end
              writeVideo(vw, frm);
          end
          if isvalid(hWB), waitbar(ii/nF, hWB); end
      end

      if isvalid(hWB), close(hWB); end
      if doSave && ~isempty(vw)
          close(vw);
          fprintf('>> 영상 저장 완료: %s\n', savePath);
      end
      disp('>> 애니메이션 완료.');
  end
end


%% ==========================================================
%% 🛠 [핵심] target_frame 기준 백워드 라그랑지안 누적 변형률 (기존 로직 동일)
%% ==========================================================
function Eps2D = local_computeAccumStrain(pivData, targetFrame, mmPerPx, X_mm, Y_mm, dx, dy, trueMask)
  Px  = X_mm(:);  Py = Y_mm(:);
  Eps = zeros(size(Px));

  for k = targetFrame:-1:1
      Uk = double(pivData.U(:,:,k)) * mmPerPx;
      Vk = double(pivData.V(:,:,k)) * mmPerPx;

      % NaN(마스크) 보존
      isMasked = isnan(Uk);
      Uk(isMasked) = NaN;  Vk(isMasked) = NaN;

      % 결측치 인지형 편측 미분 → 변형률 증분(rate가 아닌 프레임당 증분)
      [dUdx, dUdy] = local_nanGradient(Uk, dx, dy);
      [dVdx, dVdy] = local_nanGradient(Vk, dx, dy);
      deps_xx  = dUdx;
      deps_yy  = dVdy;
      deps_xy  = 0.5 * (dUdy + dVdx);
      deps_eff = sqrt((2/3) * (deps_xx.^2 + deps_yy.^2 + 2*deps_xy.^2));

      % 현재 입자 위치에서 증분 적분
      deps_p = interp2(X_mm, Y_mm, deps_eff, Px, Py, 'linear', NaN);
      v = ~isnan(deps_p);
      Eps(v) = Eps(v) + deps_p(v);

      if k == 1, break; end

      % 역방향 1스텝 이류 (마스크 메움값으로 위치 갱신)
      U_filled = inpaint_nans(Uk, 4);
      V_filled = inpaint_nans(Vk, 4);
      Up = interp2(X_mm, Y_mm, U_filled, Px, Py, 'linear', 0);
      Vp = interp2(X_mm, Y_mm, V_filled, Px, Py, 'linear', 0);
      Px_new = Px - Up;
      Py_new = Py - Vp;

      % 장애물(마스크) 충돌 입자 → 각도 탐색으로 우회 (기존 로직 동일)
      destChk = interp2(X_mm, Y_mm, Uk, Px_new, Py_new, 'nearest', NaN);
      hit     = isnan(destChk) & ~isnan(Px);
      hi      = find(hit);
      if ~isempty(hi)
          spd  = sqrt(Up(hi).^2 + Vp(hi).^2);
          ang0 = atan2(-Vp(hi), -Up(hi));
          angs = [5,-5,15,-15,30,-30,45,-45,60,-60,75,-75,89,-89] * (pi/180);

          Pxc = Px(hi);  Pyc = Py(hi);
          Pxr = Pxc;     Pyr = Pyc;
          res = false(numel(hi), 1);

          for ao = angs
              if all(res), break; end
              un = ~res;
              at = ang0(un) + ao;
              xt = Pxc(un) + cos(at) .* spd(un);
              yt = Pyc(un) + sin(at) .* spd(un);
              tv = ~isnan(interp2(X_mm, Y_mm, Uk, xt, yt, 'nearest', NaN));

              gi = find(un);  gv = gi(tv);
              Pxr(gv) = xt(tv);  Pyr(gv) = yt(tv);  res(gv) = true;
          end
          Px_new(hi) = Pxr;  Py_new(hi) = Pyr;
      end

      Px = Px_new;  Py = Py_new;
  end

  Eps2D = reshape(Eps, size(X_mm));
  Eps2D(trueMask) = NaN;     % 영구 마스크(공구 등) 제거
end


%% ==========================================================
%% 🛠 결측치 인지형 편측 미분 (NaN-Aware Gradient)
%% ==========================================================
function [dFdx, dFdy] = local_nanGradient(F, dx, dy)
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
          elseif has_left
              dFdx(i,j) = (F(i, j) - F(i, j-1)) / dx;
          elseif has_right
              dFdx(i,j) = (F(i, j+1) - F(i, j)) / dx;
          end

          has_up   = (i > 1)  && ~isnan(F(i-1, j));
          has_down = (i < Ny) && ~isnan(F(i+1, j));
          if has_up && has_down
              dFdy(i,j) = (F(i+1, j) - F(i-1, j)) / (2 * dy);
          elseif has_up
              dFdy(i,j) = (F(i, j) - F(i-1, j)) / dy;
          elseif has_down
              dFdy(i,j) = (F(i+1, j) - F(i, j)) / dy;
          end
      end
  end
end


%% ==========================================================
%% 🛠 영구 마스크: 전 프레임에서 (U=V=0) 또는 NaN 인 화소 (공구 등)
%% ==========================================================
function tm = local_computePermanentMask(pivData, Ny, Nx, Nt)
  tm = true(Ny, Nx);
  for k = 1:Nt
      Uk = double(pivData.U(:,:,k));
      Vk = double(pivData.V(:,:,k));
      tm = tm & ((Uk == 0 & Vk == 0) | isnan(Uk));
  end
end


%% ==========================================================
%% 🛠 배경 이미지 파일 목록 구성 (1회만) — imFilename2 → imFilename1 → imagePath
%% ==========================================================
function fl = local_buildFileList(pivData, Nt)
  fl = {};
  for f = {'imFilename2', 'imFilename1'}
      fn = f{1};
      if isfield(pivData, fn)
          val = pivData.(fn);
          if iscell(val) && ~isempty(val)
              fl = val(:); return;                                  % 프레임별 cell
          elseif (ischar(val) || isstring(val)) && exist(char(val), 'file')
              fl = repmat({char(val)}, Nt, 1); return;              % 단일 파일
          end
      end
  end
  if isfield(pivData, 'imagePath') && exist(pivData.imagePath, 'dir')
      for ext = {'*.png', '*.bmp', '*.tif', '*.tiff', '*.jpg'}
          D = dir(fullfile(pivData.imagePath, ext{1}));
          if ~isempty(D)
              [~, si] = sort({D.name});
              fl = fullfile(pivData.imagePath, {D(si).name})';
              return;
          end
      end
  end
end


%% ==========================================================
%% 🛠 프레임 배경 이미지 로드 (RGB 보장)
%% ==========================================================
function img = local_loadBgImage(fileList, frame)
  img = [];
  if isempty(fileList), return; end
  idx = min(max(frame, 1), numel(fileList));
  fn  = fileList{idx};
  if (ischar(fn) || isstring(fn)) && exist(char(fn), 'file')
      try
          img = imread(char(fn));
          if size(img, 3) == 1, img = cat(3, img, img, img); end   % truecolor 화 (컬러맵 비충돌)
      catch
          img = [];
      end
  end
end


%% ==========================================================
%% 🛠 변형률 필드 1장 그리기 (배경 + contourf, 색 스케일 고정)
%% ==========================================================
function local_drawStrain(ax, bg, X_mm, Y_mm, Eps2D, x_world, y_world, levels, alphaVal, cmap, climv)
  cla(ax);
  hold(ax, 'on');

  if ~isempty(bg)
      image('Parent', ax, 'XData', x_world, 'YData', y_world, 'CData', bg);  % truecolor 배경
  end
  set(ax, 'YDir', 'reverse');

  % ★ 레벨을 [climv]에 고정 → 프레임 간 색 스케일 일관 (계단 대신 부드러운 그라데이션)
  lv = linspace(climv(1), climv(2), levels);
  [~, hC] = contourf(ax, X_mm, Y_mm, Eps2D, lv, 'LineStyle', 'none');
  try, alpha(hC, alphaVal); catch, end   % 등고선 채움 투명도 (배경 비침)

  daspect(ax, [1 1 1]);                   % 정사각 픽셀(axis equal과 한계 충돌 방지)
  box(ax, 'on');
  colormap(ax, cmap);
  caxis(ax, climv);                       % ★ 0~6 고정
  hold(ax, 'off');
end


%% ==========================================================
%% 🛠 컬러바 스타일 (참고 사진과 동일: 0/2/4/6 눈금, ε_eff)
%% ==========================================================
function local_styleColorbar(cb, climv)
  cb.Limits = climv;
  cb.Ticks  = linspace(climv(1), climv(2), 4);   % 0, 2, 4, 6
  ylabel(cb, '$\epsilon_{eff}$', 'Interpreter', 'latex', 'FontSize', 14);
end