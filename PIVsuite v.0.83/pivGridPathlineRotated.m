function pivGridPathlineRotated(pivData, fileList)
% pivGridPathlineRotated - 임의의 각도로 회전된 초기 직사각형 영역을 기반으로
% 연속적인 PIV 그리드(Pathlines & Timelines)를 추적합니다.
%
% [업데이트 내역]
%   v4: 독립 실행 지원 (함수 에디터 "Run" 버튼으로 바로 실행 가능)
%   v4: 그리드선 색상을 초록→시안→옐로우→빨강 순환으로 지정 (가시성 향상)
%   v4: inpaint_nans로 불량 NaN 보간 처리 (마스크/벽면과 분리)

%% ================================================================
%% 0) [독립 실행 지원] 인수 없이 실행 시 워크스페이스에서 자동 로드
%% ================================================================
  if nargin < 1
    try
      pivData = evalin('base', 'pivData');
      fprintf('[자동 로드] 워크스페이스에서 pivData 불러옴.\n');
    catch
      [f, p] = uigetfile('*.mat', 'pivData가 저장된 .mat 파일을 선택하세요');
      if isequal(f,0), disp('취소됨.'); return; end
      S  = load(fullfile(p,f));
      fn = fieldnames(S);
      pivData = S.(fn{1});
    end
  end

  if nargin < 2
    try
      fileList = evalin('base', 'fileList');
      fprintf('[자동 로드] 워크스페이스에서 fileList 불러옴 (%d개).\n', numel(fileList));
    catch
      [files, fpath] = uigetfile( ...
        {'*.tif;*.tiff;*.png;*.bmp;*.jpg','이미지 파일'}, ...
        '배경 이미지 선택 (Ctrl 다중 선택)', 'MultiSelect','on');
      if isequal(files,0), disp('취소됨.'); return; end
      if ischar(files), files = {files}; end
      fileList = sort(cellfun(@(f) fullfile(fpath,f), files, 'UniformOutput',false));
    end
  end

%% ================================================================
%% 1) 기본 파라미터
%% ================================================================
  delay = 0.05;   % 프레임 재생 지연 (초)

  % 그리드선 순환 색상 정의: 초록 → 시안 → 옐로우 → 빨강
  % 인접한 선끼리 색이 달라서 셀 경계가 명확히 구분됨
  lineColors = {[0.1  1.0  0.1], ...   % 초록
                [0.0  1.0  1.0], ...   % 시안
                [1.0  1.0  0.0], ...   % 옐로우
                [1.0  0.3  0.3]};      % 빨강

%% ================================================================
%% 2) Nt 및 입력 검증
%% ================================================================
  if isfield(pivData,'Nt'), Nt = pivData.Nt;
  else, Nt = size(pivData.U,3); end

  if ~iscell(fileList) || isempty(fileList)
    error('fileList는 이미지 경로 cell array여야 합니다.');
  end
  nBg = numel(fileList);

%% ================================================================
%% 3) 분석 프레임 범위 설정
%% ================================================================
  prompt     = {'시작 프레임:', sprintf('종료 프레임 (최대 %d):', Nt)};
  ans_dialog = inputdlg(prompt, '분석 프레임 구간 설정', 1, {'1', num2str(Nt)});
  if isempty(ans_dialog), disp('취소됨.'); return; end

  start_frame = round(str2double(ans_dialog{1}));
  end_frame   = round(str2double(ans_dialog{2}));
  if isnan(start_frame) || start_frame < 1,  start_frame = 1;  end
  if isnan(end_frame)   || end_frame   > Nt, end_frame   = Nt; end
  if start_frame > end_frame
    [start_frame, end_frame] = deal(end_frame, start_frame);
  end
  N_frames = end_frame - start_frame + 1;

%% ================================================================
%% 4) PIV 그리드 기본 정보
%% ================================================================
  X0 = double(pivData.X);
  Y0 = double(pivData.Y);
  dx = abs(X0(1,2) - X0(1,1));
  if dx == 0, dx = abs(Y0(2,1) - Y0(1,1)); end

%% ================================================================
%% 5) 마스크 사전 계산
%% - 전 프레임 공통 NaN = 벽면/마스크  → No-slip 유지
%% - 일부 프레임만 NaN  = 계산 실패   → inpaint 보간 대상
%% ================================================================
  wall_mask_global = all(isnan(pivData.U), 3);

%% ================================================================
%% 6) 사용자 상호작용: 기준선 & 두께 클릭
%% ================================================================
  bg0 = imread(fileList{min(start_frame, nBg)});
  h0  = figure('Name','자유 각도 직사각형 선택');
  imshow(bg0, 'XData',[1 pivData.imSizeX], 'YData',[1 pivData.imSizeY]);
  set(gca,'YDir','reverse'); axis image; hold on;

  title('STEP 1: 유동 기준선을 자유로운 각도로 긋고 더블클릭');
  h_line = imline(gca);
  pos    = wait(h_line);
  x1 = pos(1,1); y1 = pos(1,2);
  x2 = pos(2,1); y2 = pos(2,2);

  title('STEP 2: 직사각형 두께를 마우스로 클릭');
  [cx, cy] = ginput(1);

%% ================================================================
%% 7) 기하학 계산: 회전된 직사각형 정의
%% ================================================================
  v_base = [x2-x1, y2-y1];
  L_base = norm(v_base);
  v_unit = v_base / L_base;
  n_vec  = [-v_unit(2), v_unit(1)];  % 법선(수직) 벡터

  depth = dot([cx-x1, cy-y1], n_vec);
  if depth < 0, n_vec = -n_vec; depth = -depth; end

  P3 = [x2,y2]+depth*n_vec; P4 = [x1,y1]+depth*n_vec;
  patch([x1 x2 P3(1) P4(1)],[y1 y2 P3(2) P4(2)],'y',...
    'FaceAlpha',0.15,'EdgeColor','y','LineWidth',2);
  pause(1.0); close(h0);

%% ================================================================
%% 8) 그리드 배열 초기화
%% ================================================================
  num_seeds     = max(2, round(L_base/dx)+1);
  num_init_cols = max(1, round(depth/dx)+1);

  X_anchor = linspace(x1,x2,num_seeds)';
  Y_anchor = linspace(y1,y2,num_seeds)';

  total_cols = N_frames + num_init_cols;
  X_grid     = NaN(num_seeds, total_cols);
  Y_grid     = NaN(num_seeds, total_cols);

  curr_start = N_frames + 1;
  curr_end   = N_frames + num_init_cols;

  for c = 1:num_init_cols
    X_grid(:, curr_start+c-1) = X_anchor + n_vec(1)*dx*(c-1);
    Y_grid(:, curr_start+c-1) = Y_anchor + n_vec(2)*dx*(c-1);
  end
  feed_accum = 0;

%% ================================================================
%% 9) Figure 설정
%% ================================================================
  hFig = figure('Renderer','opengl', ...
    'Name', sprintf('Grid Tracking (Frames: %d~%d)', start_frame, end_frame));
  ax = axes('Parent',hFig);
  hold(ax,'on');
  set(ax,'YDir','reverse','DataAspectRatio',[1 1 1]);

  bg1 = imread(fileList{min(start_frame,nBg)});
  hIm = imshow(bg1,'Parent',ax,...
    'XData',[1 pivData.imSizeX],'YData',[1 pivData.imSizeY],...
    'InitialMagnification','fit');

  hLines = gobjects(0);

%% ================================================================
%% 10) 메인 루프: 추적 + 순환 컬러 그리드 렌더링
%% ================================================================
  for t = start_frame:end_frame

    % ---- [A] 배경 이미지 업데이트 ----
    bg = imread(fileList{min(t,nBg)});
    set(hIm,'CData',bg);

    % ---- [B] 이전 프레임 그리드선 삭제 ----
    if ~isempty(hLines)
      delete(hLines(isgraphics(hLines)));
    end
    hLines = gobjects(0);

    % ---- [C] 속도장 로드 & NaN 처리 ----
    Ut = double(pivData.U(:,:,t));
    Vt = double(pivData.V(:,:,t));

    % 마스크 영역 식별 (Status 비트1 = 벽면/마스크)
    if isfield(pivData,'Status')
      st_idx   = min(t, size(pivData.Status,3));
      wall_now = logical(bitget(uint8(pivData.Status(:,:,st_idx)), 1));
    else
      wall_now = wall_mask_global;
    end

    % 불량 NaN → inpaint_nans 공간 보간 후, 벽면만 No-slip 재적용
    Ut = inpaint_nans(Ut, 4);
    Vt = inpaint_nans(Vt, 4);
    Ut(wall_now) = 0;
    Vt(wall_now) = 0;

    mean_U = mean(Ut(:));
    mean_V = mean(Vt(:));

    % ---- [D] 순환 컬러 그리드선 그리기 ----

    % (a) 패스라인 (가로선)
    %     씨앗 row 번호 i 로 색상 순환
    %     → 인접 패스라인끼리 다른 색 → 세로 방향 셀 경계 구분
    for i = 1:num_seeds
      col = lineColors{ mod(i-1, 4)+1 };
      px  = [X_anchor(i), X_grid(i, curr_start:curr_end)];
      py  = [Y_anchor(i), Y_grid(i, curr_start:curr_end)];
      hLines(end+1) = plot(ax, px, py, '-', 'Color', col, 'LineWidth', 1.2);
    end

    % (b) 타임라인 (세로선)
    %     X_grid 배열 내 절대 열 인덱스 j 로 색상 순환
    %     → curr_start가 줄어들며 새 열이 추가돼도 색상이 자연스럽게 이어짐
    for j = curr_start:curr_end
      col = lineColors{ mod(j-1, 4)+1 };
      hLines(end+1) = plot(ax, X_grid(:,j), Y_grid(:,j), '-', 'Color', col, 'LineWidth', 1.2);
    end

    % (c) 앵커(유입구) 기준선 - 흰색 고정
    hLines(end+1) = plot(ax, X_anchor, Y_anchor, 'w-', 'LineWidth', 1.8);

    title(ax, sprintf('Frame %d / %d', t, end_frame), 'FontSize',14);
    drawnow;
    pause(delay);
    if ~ishandle(hFig), break; end

    % ---- [E] 라그랑주 추적 계산 (마지막 프레임 전까지) ----
    if t < end_frame

      % 그리드 전체 이동
      U_interp = interp2(X0,Y0,Ut, X_grid,Y_grid,'linear',mean_U);
      V_interp = interp2(X0,Y0,Vt, X_grid,Y_grid,'linear',mean_V);
      X_grid   = X_grid + U_interp;
      Y_grid   = Y_grid + V_interp;

      % 앵커에서 유속 방향 계산
      U_anch = interp2(X0,Y0,Ut, X_anchor,Y_anchor,'linear',mean_U);
      V_anch = interp2(X0,Y0,Vt, X_anchor,Y_anchor,'linear',mean_V);

      u_dir   = nanmean(U_anch);
      v_dir   = nanmean(V_anch);
      mag_dir = sqrt(u_dir^2 + v_dir^2);
      if mag_dir > 0
        u_dir = u_dir / mag_dir;
        v_dir = v_dir / mag_dir;
      else
        u_dir = n_vec(1); v_dir = n_vec(2);
      end

      % 서브픽셀 누산: dx 초과 시 새 타임라인 열 주입
      u_in = nanmean(sqrt(U_anch.^2 + V_anch.^2));
      if isnan(u_in) || u_in == 0, u_in = 1; end
      feed_accum = feed_accum + u_in;

      while feed_accum >= dx
        overshoot  = feed_accum - dx;
        curr_start = curr_start - 1;
        X_grid(:, curr_start) = X_anchor + u_dir*overshoot;
        Y_grid(:, curr_start) = Y_anchor + v_dir*overshoot;
        feed_accum = overshoot;
      end

    end % if t < end_frame

  end % for t

end % function
