function pivGridPathlineStretch(pivData, fileList)
% pivGridPathlineStretch
% ----------------------------------------------------------------------
% pivGridPathlineRotated 의 단순화 버전.
% 각 변의 늘어남 비율 (stretch ratio) λ = L_현재 / L_기준 만 계산하여
% 변의 색상만 변경한다. 격자는 절대 사라지지 않는다.
%
% [Al 6061-T6 기준 임계값]
%   λ_yield    = 1.05  (5% 늘어남, 항복 영역 시작 → 주황)
%   λ_fracture = 1.17  (17% 늘어남, ductile 파단 변형률 → 빨강)
%
% [색상 규칙]
%   λ < λ_yield                      : 초록 (정상)
%   λ_yield ≤ λ < λ_fracture         : 주황 (항복)
%   λ ≥ λ_fracture                   : 빨강 (과도 늘어남)
%
% [성능]
%   매 프레임 모든 변을 3개 카테고리로 분류 후 카테고리당 1회 plot
%   → 변 수가 늘어나도 plot 호출 수는 일정 (= 4회 + 앵커)
%
% 입력:
%   pivData  : pivAnalyzeImageSequence 결과 (X, Y, U, V, Status, imSizeX, imSizeY, Nt)
%   fileList : 배경 이미지 경로 cell array
% ----------------------------------------------------------------------

%% ====================================================================
%% 0) 인수 자동 로드
%% ====================================================================
  if nargin < 1
    try
      pivData = evalin('base', 'pivData');
      fprintf('[자동 로드] 워크스페이스에서 pivData 불러옴.\n');
    catch
      [f, p] = uigetfile('*.mat', 'pivData가 저장된 .mat 파일 선택');
      if isequal(f,0), disp('취소됨.'); return; end
      S  = load(fullfile(p,f));
      fn = fieldnames(S);
      pivData = S.(fn{1});
    end
  end
  if nargin < 2
    try
      fileList = evalin('base', 'fileList');
      fprintf('[자동 로드] 워크스페이스에서 fileList (%d개) 불러옴.\n', numel(fileList));
    catch
      [files, fpath] = uigetfile( ...
        {'*.tif;*.tiff;*.png;*.bmp;*.jpg','이미지 파일'}, ...
        '배경 이미지 선택', 'MultiSelect','on');
      if isequal(files,0), disp('취소됨.'); return; end
      if ischar(files), files = {files}; end
      fileList = sort(cellfun(@(f) fullfile(fpath,f), files, 'UniformOutput',false));
    end
  end

%% ====================================================================
%% 1) 재료 임계값 (Aluminum 6061-T6)
%% ====================================================================
  mat.name            = 'Al 6061-T6';
  mat.lambda_yield    = 1.5;     % 5% 늘어남: 항복 시작 (주황)
  mat.lambda_fracture = 1.8;     % 17% 늘어남: 파단 변형률 (빨강)

%% ====================================================================
%% 2) 시각화 옵션
%% ====================================================================
  opt.delay        = 0.05;
  opt.colNormal    = [0.10 1.00 0.10];   % 초록 (정상, λ < 1.05)
  opt.colYielded   = [1.00 0.65 0.10];   % 주황 (1.05 ≤ λ < 1.17)
  opt.colFracture  = [1.00 0.10 0.10];   % 빨강 (λ ≥ 1.17)
  opt.lineWidth    = 1.2;
  opt.anchorColor  = [1 1 1];            % 흰색 (앵커)
  opt.anchorWidth  = 1.8;

%% ====================================================================
%% 3) Nt / 입력 검증
%% ====================================================================
  if isfield(pivData,'Nt'), Nt = pivData.Nt;
  else, Nt = size(pivData.U,3); end
  if ~iscell(fileList) || isempty(fileList)
    error('fileList는 이미지 경로 cell array여야 합니다.');
  end
  nBg = numel(fileList);

%% ====================================================================
%% 4) 분석 프레임 범위
%% ====================================================================
  prompt = {'시작 프레임:', sprintf('종료 프레임 (최대 %d):', Nt)};
  ans_dialog = inputdlg(prompt, '분석 프레임 구간', 1, {'1', num2str(Nt)});
  if isempty(ans_dialog), disp('취소됨.'); return; end
  start_frame = round(str2double(ans_dialog{1}));
  end_frame   = round(str2double(ans_dialog{2}));
  if isnan(start_frame) || start_frame < 1, start_frame = 1; end
  if isnan(end_frame)   || end_frame   > Nt, end_frame   = Nt; end
  if start_frame > end_frame
    [start_frame, end_frame] = deal(end_frame, start_frame);
  end
  N_frames = end_frame - start_frame + 1;

%% ====================================================================
%% 5) PIV 그리드 정보
%% ====================================================================
  X0 = double(pivData.X);
  Y0 = double(pivData.Y);
  dx_piv = abs(X0(1,2) - X0(1,1));
  if dx_piv == 0, dx_piv = abs(Y0(2,1) - Y0(1,1)); end
  wall_mask_global = all(isnan(pivData.U), 3);

%% ====================================================================
%% 6) 사용자 입력: 기준선 + 두께
%% ====================================================================
  bg0 = imread(fileList{min(start_frame, nBg)});
  h0 = figure('Name','자유 각도 직사각형 선택');
  imshow(bg0,'XData',[1 pivData.imSizeX],'YData',[1 pivData.imSizeY]);
  set(gca,'YDir','reverse'); axis image; hold on;
  title('STEP 1: 시편 길이 방향 기준선 그린 후 더블클릭');
  h_line = imline(gca);
  pos = wait(h_line);
  x1 = pos(1,1); y1 = pos(1,2);
  x2 = pos(2,1); y2 = pos(2,2);
  title('STEP 2: 시편 두께(폭) 클릭');
  [cx, cy] = ginput(1);

%% ====================================================================
%% 7) 회전 직사각형 기하
%% ====================================================================
  v_base = [x2-x1, y2-y1];
  L_base = norm(v_base);
  v_unit = v_base / L_base;
  n_vec  = [-v_unit(2), v_unit(1)];
  depth = dot([cx-x1, cy-y1], n_vec);
  if depth < 0, n_vec = -n_vec; depth = -depth; end
  P3p = [x2,y2]+depth*n_vec; P4p = [x1,y1]+depth*n_vec;
  patch([x1 x2 P3p(1) P4p(1)],[y1 y2 P3p(2) P4p(2)],'y',...
    'FaceAlpha',0.15,'EdgeColor','y','LineWidth',2);
  pause(1.0); close(h0);

%% ====================================================================
%% 8) 그리드 초기화
%% ====================================================================
  num_seeds     = max(2, round(L_base/dx_piv)+1);
  num_init_cols = max(1, round(depth/dx_piv)+1);

  ds = L_base / (num_seeds-1);   % 행 사이 기준 길이 (timeline 변)
  dn = dx_piv;                   % 컬럼 사이 기준 길이 (pathline 변)

  X_anchor = linspace(x1,x2,num_seeds)';
  Y_anchor = linspace(y1,y2,num_seeds)';

  total_cols = N_frames + num_init_cols;
  X_grid = NaN(num_seeds, total_cols);
  Y_grid = NaN(num_seeds, total_cols);
  curr_start = N_frames + 1;
  curr_end   = N_frames + num_init_cols;

  for c = 1:num_init_cols
    X_grid(:, curr_start+c-1) = X_anchor + n_vec(1)*dx_piv*(c-1);
    Y_grid(:, curr_start+c-1) = Y_anchor + n_vec(2)*dx_piv*(c-1);
  end
  feed_accum = 0;

%% ====================================================================
%% 9) Figure
%% ====================================================================
  hFig = figure('Renderer','opengl','Name', ...
    sprintf('Stretch Coloring (%s)  Frames %d~%d', mat.name, start_frame, end_frame));
  ax = axes('Parent',hFig);
  hold(ax,'on');
  set(ax,'YDir','reverse','DataAspectRatio',[1 1 1]);

  bg1 = imread(fileList{min(start_frame,nBg)});
  hIm = imshow(bg1,'Parent',ax,...
    'XData',[1 pivData.imSizeX],'YData',[1 pivData.imSizeY],...
    'InitialMagnification','fit');

  hLines = gobjects(0);

%% ====================================================================
%% 10) 메인 루프
%% ====================================================================
  for t = start_frame:end_frame

    % --- [A] 배경 이미지 갱신 ---
    bg = imread(fileList{min(t,nBg)});
    set(hIm,'CData',bg);

    % --- [B] 이전 프레임 그래픽 삭제 ---
    if ~isempty(hLines)
      delete(hLines(isgraphics(hLines)));
    end
    hLines = gobjects(0);

    % --- [C] 속도장 로드 + NaN 처리 ---
    Ut = double(pivData.U(:,:,t));
    Vt = double(pivData.V(:,:,t));
    if isfield(pivData,'Status')
      st_idx = min(t, size(pivData.Status,3));
      wall_now = logical(bitget(uint8(pivData.Status(:,:,st_idx)), 1));
    else
      wall_now = wall_mask_global;
    end
    Ut = inpaint_nans(Ut,4);
    Vt = inpaint_nans(Vt,4);
    Ut(wall_now)=0; Vt(wall_now)=0;
    mean_U = mean(Ut(:));
    mean_V = mean(Vt(:));

    % --- [D] 모든 변(edge) 한 번에 수집 ---
    %     ALL = [x1, y1, x2, y2, L_ref] 테이블

    % (D-1) 패스라인 — anchor → curr_start
    PL_anchor = [X_anchor, Y_anchor, ...
                 X_grid(:,curr_start), Y_grid(:,curr_start), ...
                 dn*ones(num_seeds,1)];

    % (D-2) 패스라인 — 그리드 컬럼 사이
    if curr_end > curr_start
      J1 = curr_start:curr_end-1;
      J2 = curr_start+1:curr_end;
      PG_x1 = X_grid(:, J1);  PG_y1 = Y_grid(:, J1);
      PG_x2 = X_grid(:, J2);  PG_y2 = Y_grid(:, J2);
      PL_grid = [PG_x1(:), PG_y1(:), PG_x2(:), PG_y2(:), ...
                 dn*ones(numel(PG_x1),1)];
    else
      PL_grid = zeros(0,5);
    end

    % (D-3) 타임라인 — 행 사이
    TL_x1 = X_grid(1:end-1, curr_start:curr_end);
    TL_y1 = Y_grid(1:end-1, curr_start:curr_end);
    TL_x2 = X_grid(2:end,   curr_start:curr_end);
    TL_y2 = Y_grid(2:end,   curr_start:curr_end);
    TL = [TL_x1(:), TL_y1(:), TL_x2(:), TL_y2(:), ...
          ds*ones(numel(TL_x1),1)];

    % 모든 변 합치기
    ALL = [PL_anchor; PL_grid; TL];

    % --- [E] 늘어남 비율 λ 계산 + 카테고리 분류 ---
    L_curr = hypot(ALL(:,3) - ALL(:,1), ALL(:,4) - ALL(:,2));
    lambda = L_curr ./ ALL(:,5);

    % NaN 보호 (앵커 첫 프레임 등 길이가 0인 경우 → 정상 처리)
    lambda(~isfinite(lambda)) = 0;

    mask_N = lambda <  mat.lambda_yield;
    mask_Y = (lambda >= mat.lambda_yield) & (lambda < mat.lambda_fracture);
    mask_F = lambda >= mat.lambda_fracture;

    % --- [F] 카테고리별 NaN 분리 좌표 만들기 ---
    [Nx, Ny] = packEdges(ALL, mask_N);
    [Yx, Yy] = packEdges(ALL, mask_Y);
    [Fx, Fy] = packEdges(ALL, mask_F);

    % --- [G] 한 번에 그리기 (3 plot calls + 앵커) ---
    if ~isempty(Nx)
      hLines(end+1) = plot(ax, Nx, Ny, '-', ...
        'Color', opt.colNormal,   'LineWidth', opt.lineWidth);
    end
    if ~isempty(Yx)
      hLines(end+1) = plot(ax, Yx, Yy, '-', ...
        'Color', opt.colYielded,  'LineWidth', opt.lineWidth);
    end
    if ~isempty(Fx)
      hLines(end+1) = plot(ax, Fx, Fy, '-', ...
        'Color', opt.colFracture, 'LineWidth', opt.lineWidth);
    end
    % 앵커 기준선 (흰색, 항상 표시)
    hLines(end+1) = plot(ax, X_anchor, Y_anchor, '-', ...
      'Color', opt.anchorColor, 'LineWidth', opt.anchorWidth);

    % 타이틀: 진행도 + 통계
    nF = sum(mask_F);
    nY = sum(mask_Y);
    nN = sum(mask_N);
    title(ax, sprintf(['Frame %d/%d   |   %s   |   ' ...
                       '\\lambda_y=%.2f, \\lambda_f=%.2f   |   ' ...
                       'Normal: %d   Yield: %d   Stretched: %d'], ...
                      t, end_frame, mat.name, ...
                      mat.lambda_yield, mat.lambda_fracture, nN, nY, nF), ...
                      'FontSize', 12);
    drawnow;
    pause(opt.delay);
    if ~ishandle(hFig), break; end

    % --- [H] 라그랑주 추적 (마지막 프레임 전까지) ---
    if t < end_frame
      U_interp = interp2(X0,Y0,Ut, X_grid,Y_grid,'linear',mean_U);
      V_interp = interp2(X0,Y0,Vt, X_grid,Y_grid,'linear',mean_V);
      X_grid = X_grid + U_interp;
      Y_grid = Y_grid + V_interp;

      U_anch = interp2(X0,Y0,Ut, X_anchor,Y_anchor,'linear',mean_U);
      V_anch = interp2(X0,Y0,Vt, X_anchor,Y_anchor,'linear',mean_V);
      u_dir = nanmean(U_anch); v_dir = nanmean(V_anch);
      mag_dir = sqrt(u_dir^2 + v_dir^2);
      if mag_dir > 0
        u_dir = u_dir/mag_dir;  v_dir = v_dir/mag_dir;
      else
        u_dir = n_vec(1); v_dir = n_vec(2);
      end

      u_in = nanmean(sqrt(U_anch.^2 + V_anch.^2));
      if isnan(u_in) || u_in == 0, u_in = 1; end
      feed_accum = feed_accum + u_in;
      while feed_accum >= dx_piv
        overshoot = feed_accum - dx_piv;
        curr_start = curr_start - 1;
        X_grid(:, curr_start) = X_anchor + u_dir*overshoot;
        Y_grid(:, curr_start) = Y_anchor + v_dir*overshoot;
        feed_accum = overshoot;
      end
    end

  end % main for-loop

end % main function


%% =====================================================
%% 헬퍼: NaN-분리된 plot 좌표 생성
%% =====================================================
function [xs, ys] = packEdges(ALL, mask)
% ALL(:, [1 2 3 4]) = [x1 y1 x2 y2], mask로 선택된 행만 추출하여
% [x1; x2; NaN; x1; x2; NaN; ...] 형식으로 반환 → plot 1회로 다중 선분 그리기
  if ~any(mask)
    xs = []; ys = [];
    return;
  end
  E = ALL(mask, 1:4);
  n = size(E,1);
  xs = reshape([E(:,1)'; E(:,3)'; nan(1,n)], [], 1);
  ys = reshape([E(:,2)'; E(:,4)'; nan(1,n)], [], 1);
end
