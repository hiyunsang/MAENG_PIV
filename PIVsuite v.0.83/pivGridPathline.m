function pivGridPathline(pivData, fileList)
% pivGridPathline - 축 정렬 직사각형 영역에서 연속적인 PIV 그리드를 추적하고
% 접선 슬립(Tangential Sliding) 메커니즘으로 벽면 충돌을 회피합니다.
%
% [업데이트 내역]
%   v2: 독립 실행 지원 (함수 에디터 "Run" 버튼으로 바로 실행 가능)
%   v2: 그리드선 색상을 초록→시안→옐로우→빨강 순환 (가시성 향상)
%   v2: NaN 분리 처리 - 진짜 벽면(Status 비트1)과 계산 실패 NaN을 구분
%       → 계산 실패는 inpaint_nans로 보간, 슬립은 진짜 벽면에만 적용
%       → 그리드 일그러짐 완화

%% ================================================================
%% 0) [독립 실행 지원] 인수 없이 실행 시 워크스페이스/파일에서 자동 로드
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
  delay = 0.1;   % 프레임 재생 지연 (초)

  % 그리드선 순환 색상: 초록 → 시안 → 옐로우 → 빨강
  lineColors = {[0.1  1.0  0.1], ...   % 초록
                [0.0  1.0  1.0], ...   % 시안
                [1.0  1.0  0.0], ...   % 옐로우
                [1.0  0.3  0.3]};      % 빨강
  numColors = length(lineColors);

%% ================================================================
%% 2) Nt 및 입력 검증
%% ================================================================
  if isfield(pivData,'Nt'), max_Nt = pivData.Nt;
  else, max_Nt = size(pivData.U,3); end

  if ~iscell(fileList) || isempty(fileList)
    error('fileList는 이미지 경로 cell array여야 합니다.');
  end
  nBg = numel(fileList);

%% ================================================================
%% 3) 분석 프레임 범위 설정 (다이얼로그)
%% ================================================================
  prompt     = {'시작 프레임:', sprintf('종료 프레임 (최대 %d):', max_Nt)};
  ans_dialog = inputdlg(prompt, '분석 프레임 구간 설정', 1, {'1', num2str(max_Nt)});
  if isempty(ans_dialog), disp('취소됨.'); return; end

  start_frame = round(str2double(ans_dialog{1}));
  end_frame   = round(str2double(ans_dialog{2}));
  if isnan(start_frame) || start_frame < 1,      start_frame = 1;      end
  if isnan(end_frame)   || end_frame   > max_Nt, end_frame   = max_Nt; end
  if start_frame > end_frame
    [start_frame, end_frame] = deal(end_frame, start_frame);
  end
  fprintf('>> Frame %d 부터 %d 까지 해석을 진행합니다.\n', start_frame, end_frame);

%% ================================================================
%% 4) PIV 그리드 기본 정보
%% ================================================================
  X0 = double(pivData.X);
  Y0 = double(pivData.Y);
  dx = abs(X0(1,2) - X0(1,1));
  if dx == 0, dx = abs(Y0(2,1) - Y0(1,1)); end

%% ================================================================
%% 5) 벽면 마스크 사전 계산
%% - 전 프레임 공통 NaN = 진짜 벽면/마스크  → 슬립 적용 대상
%% - 일부 프레임만 NaN  = 계산 실패          → inpaint 보간 대상
%% ================================================================
  wall_mask_global = all(isnan(pivData.U), 3);

%% ================================================================
%% 6) 사용자 ROI 선택 (축 정렬 직사각형)
%% ================================================================
  bg0 = imread(fileList{min(start_frame, nBg)});
  h0  = figure('Name','관심 영역 선택');
  imshow(bg0, 'XData',[1 pivData.imSizeX], 'YData',[1 pivData.imSizeY]);
  set(gca,'YDir','reverse'); axis image; hold on;
  title(sprintf('[Frame %d] 추적할 초기 사각형 영역을 드래그하세요', start_frame));

  pos = wait(imrect);
  close(h0);

  xmin = pos(1); xmax = pos(1)+pos(3);
  ymin = pos(2); ymax = pos(2)+pos(4);

  col_idx = find(X0(1,:) >= xmin & X0(1,:) <= xmax);
  row_idx = find(Y0(:,1) >= ymin & Y0(:,1) <= ymax);

  if isempty(col_idx) || isempty(row_idx)
    error('선택한 영역 내에 PIV 격자점이 없습니다. 더 크게 드래그해 주세요.');
  end

%% ================================================================
%% 7) 그리드 초기화
%% ================================================================
  X_anchor  = X0(1, col_idx(1));   % 좌측 기준 X 좌표 (스칼라)
  Y_anchor  = Y0(row_idx, 1);      % 행별 Y 좌표 (열벡터)
  num_seeds = length(row_idx);

  X_grid = X0(row_idx, col_idx);
  Y_grid = Y0(row_idx, col_idx);

  feed_accum   = 0;   % 서브픽셀 누산기
  color_offset = 0;   % 새 열 추가 시 색상 일관성 유지 오프셋

%% ================================================================
%% 8) Figure 설정
%% ================================================================
  hFig = figure('Renderer','opengl', ...
    'Name', sprintf('Grid Tracking (Frames: %d~%d)', start_frame, end_frame));
  ax = axes('Parent',hFig);
  hold(ax,'on');
  set(ax,'YDir','reverse','DataAspectRatio',[1 1 1]);

  hIm = imshow(bg0,'Parent',ax, ...
    'XData',[1 pivData.imSizeX], 'YData',[1 pivData.imSizeY], ...
    'InitialMagnification','fit');

  hLines = gobjects(0);

%% ================================================================
%% 9) 메인 루프: 추적 + 슬립 + 순환 컬러 렌더링
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

    % ---- [C] 순환 컬러로 그리드선 그리기 ----

    % (a) 가로선 (패스라인): row 인덱스 i 기준 색상 순환
    for i = 1:num_seeds
      c_idx = mod(i-1, numColors) + 1;
      plot_X = [X_anchor, X_grid(i, :)];
      plot_Y = [Y_anchor(i), Y_grid(i, :)];
      hLines(end+1) = plot(ax, plot_X, plot_Y, '-', ...
        'Color', lineColors{c_idx}, 'LineWidth', 1.2);
    end

    % (b) 세로선 (타임라인): 열 인덱스 j + color_offset 기준
    %     → 배열 앞에 새 열이 prepend되어도 기존 선들 색상 고정
    for j = 1:size(X_grid, 2)
      c_idx = mod(j - 1 + color_offset, numColors) + 1;
      hLines(end+1) = plot(ax, X_grid(:, j), Y_grid(:, j), '-', ...
        'Color', lineColors{c_idx}, 'LineWidth', 1.2);
    end

    % (c) 앵커(유입구) 기준선 - 흰색 고정
    hLines(end+1) = plot(ax, X_anchor*ones(num_seeds,1), Y_anchor, ...
      'w-', 'LineWidth', 1.8);

    title(ax, sprintf('Frame %d / %d (접선 슬라이딩 회피 적용)', t, end_frame), ...
      'FontSize', 14);
    drawnow;
    pause(delay);
    if ~ishandle(hFig), break; end

    % ---- [D] 속도장 처리 & 추적 (마지막 프레임 전까지) ----
    if t < end_frame

      Ut = double(pivData.U(:,:,t));
      Vt = double(pivData.V(:,:,t));

      % --- 진짜 벽면 식별 (Status 비트1) ---
      if isfield(pivData,'Status')
        st_idx   = min(t, size(pivData.Status, 3));
        wall_now = logical(bitget(uint8(pivData.Status(:,:,st_idx)), 1));
      else
        wall_now = wall_mask_global;
      end

      % --- 불량 NaN(계산 실패)만 보간; 벽면 NaN도 일단 보간된 상태가 됨 ---
      U_filled = inpaint_nans(Ut, 4);
      V_filled = inpaint_nans(Vt, 4);

      mean_U = mean(U_filled(:));
      mean_V = mean(V_filled(:));
      if isnan(mean_U), mean_U = 0; end
      if isnan(mean_V), mean_V = 0; end

      % --- 충돌 검사용 벽면 지표장 (진짜 벽면에만 NaN, 그 외는 0) ---
      %    이렇게 분리하면 "계산 실패 NaN" 때문에 슬립이 잘못 발동하지 않음
      wall_field           = zeros(size(X0));
      wall_field(wall_now) = NaN;

      % --- 그리드 전체 이동 (보간된 연속 유동장 사용) ---
      U_interp = interp2(X0, Y0, U_filled, X_grid, Y_grid, 'linear', mean_U);
      V_interp = interp2(X0, Y0, V_filled, X_grid, Y_grid, 'linear', mean_V);
      X_new    = X_grid + U_interp;
      Y_new    = Y_grid + V_interp;

      % ---- [E] 벡터화된 레이캐스팅 기반 접선 슬라이딩 ----
      %    wall_field 사용 → 진짜 벽면 충돌만 감지 (계산실패 NaN은 무시)
      dest_check = interp2(X0, Y0, wall_field, X_new, Y_new, 'nearest', NaN);
      hit_mask   = isnan(dest_check);
      hit_idx    = find(hit_mask);
      num_hits   = length(hit_idx);

      if num_hits > 0
        speed    = sqrt(U_interp(hit_idx).^2 + V_interp(hit_idx).^2);
        ang_orig = atan2(V_interp(hit_idx), U_interp(hit_idx));

        % 시도할 각도 후보 (소→대, 양/음 교차)
        angles = [5, -5, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 89, -89] * (pi/180);

        X_curr = X_grid(hit_idx);
        Y_curr = Y_grid(hit_idx);

        X_resolved    = X_curr;
        Y_resolved    = Y_curr;
        resolved_mask = false(num_hits, 1);

        for ang_offset = angles
          if all(resolved_mask), break; end

          unresolved = ~resolved_mask;
          ang_test   = ang_orig(unresolved) + ang_offset;

          vx_test = cos(ang_test) .* speed(unresolved);
          vy_test = sin(ang_test) .* speed(unresolved);

          x_test = X_curr(unresolved) + vx_test;
          y_test = Y_curr(unresolved) + vy_test;

          % 각도 테스트도 wall_field로 검사 (진짜 벽면만)
          test_valid = ~isnan(interp2(X0, Y0, wall_field, x_test, y_test, 'nearest', NaN));

          idx_unresolved_global = find(unresolved);
          valid_global          = idx_unresolved_global(test_valid);

          X_resolved(valid_global)    = x_test(test_valid);
          Y_resolved(valid_global)    = y_test(test_valid);
          resolved_mask(valid_global) = true;
        end

        X_new(hit_idx) = X_resolved;
        Y_new(hit_idx) = Y_resolved;
      end

      % --- 최종 그리드 위치 갱신 ---
      X_grid = X_new;
      Y_grid = Y_new;

      % ---- [F] 새 열(타임라인) 주입 ----
      U_anchor_vals = interp2(X0, Y0, U_filled, ...
        X_anchor*ones(num_seeds,1), Y_anchor, 'linear', mean_U);
      u_in = mean(abs(U_anchor_vals(~isnan(U_anchor_vals))));
      if isnan(u_in) || u_in <= 0, u_in = abs(mean_U); end
      if u_in == 0, u_in = 1; end

      feed_accum = feed_accum + u_in;

      while feed_accum >= dx
        overshoot  = feed_accum - dx;
        X_grid     = [ (X_anchor + overshoot) * ones(num_seeds, 1), X_grid ];
        Y_grid     = [ Y_anchor, Y_grid ];
        feed_accum = overshoot;

        % 새 열이 앞에 prepend되어 모든 j가 +1 밀리므로
        % offset을 -1 해줘서 기존 선의 색을 고정시킴
        color_offset = mod(color_offset - 1, numColors);
      end

    end % if t < end_frame

  end % for t

  fprintf('해석이 완료되었습니다!\n');
end
