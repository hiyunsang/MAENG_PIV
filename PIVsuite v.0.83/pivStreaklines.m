function streaklines_data = pivStreaklines()
% pivStreaklines — 연속 주입식 유맥선(Streakline) 생성기
%                  매 프레임마다 시드점에서 새 입자를 주입하고, 지금까지 주입된
%                  모든 입자를 현재 속도장으로 이동시킨 뒤 선으로 연결합니다.
%                  - Coast Limit(관성 돌파): 마스크/경계에서 일정 프레임은 직전
%                    속도로 관성 이동, 그 이상 지속되면 장애물로 보고 완전 정지
%
%   ★ pathline 코드와 동일한 UX
%     - 점 개수 지정     : 코드 최상단 파라미터로 직접 입력
%     - 직선 시드 분포   : 직선 2점 클릭 → 직선 위에 주입점 자동 등분 배치
%     - 프레임 범위 지정 : 시작/끝 프레임을 직접 입력하여 해당 구간만 추적
%     - MP4 영상 저장    : 실행 시 저장 여부(y/n)를 묻고, 원하면 MPEG-4로 기록

  %% ============================================================
  %  ★ 사용자 파라미터
  %% ============================================================
  M               = 10;   % 직선 위에 분포시킬 주입점(시드)의 개수 (최소 2)
  max_coast_frames = 3;   % 마스크 진입 후 관성 이동을 허용할 최대 프레임 수
  ANIM_PAUSE      = 0.05;  % 프레임 간 정지 시간 [s] (0이면 최대 속도)
  %% ============================================================

  if M < 2
    warning('M=%d → 직선 위에 분포시키려면 최소 2개 필요. 자동으로 2로 설정.', M);
    M = 2;
  end

  % 1. pivData 가져오기
  if evalin('base', 'exist(''pivData'', ''var'')')
    pivData = evalin('base', 'pivData');
  else
    error('Workspace에 pivData 변수가 없습니다.');
  end
  Nt = size(pivData.U, 3);

  % 2. fileList 구성 (배경 이미지용)
  if evalin('base', 'exist(''fileList'', ''var'')')
    fileList = evalin('base', 'fileList');
  elseif isfield(pivData, 'imagePath')
    fld = pivData.imagePath;
    D = dir(fullfile(fld, '*.png'));
    if isempty(D), D = dir(fullfile(fld, '*.bmp')); end
    if isempty(D), error('pivData.imagePath에 이미지가 없습니다.'); end
    [~, idx] = sort({D.name});
    fileList = fullfile(fld, {D(idx).name});
  else
    error('Workspace에 fileList가 없고, pivData.imagePath도 정의되지 않았습니다.');
  end

  if numel(fileList) < Nt
    error('fileList 개수(%d) < Nt(%d).', numel(fileList), Nt);
  elseif numel(fileList) > Nt
    fileList = fileList(1:Nt);
  end

  % ★ 2-1. 프레임 범위 입력 ----------------------------------------------
  fprintf('\n전체 프레임 수: %d\n', Nt);
  t_start = input(sprintf('시작 프레임 입력 (1 ~ %d): ', Nt));
  t_end   = input(sprintf('끝   프레임 입력 (%d ~ %d): ', max(1,round(t_start)), Nt));

  t_start = max(1,       min(round(t_start), Nt));   % 범위 보정
  t_end   = max(t_start, min(round(t_end),   Nt));
  Nf      = t_end - t_start + 1;                     % 추적할 프레임 수
  fprintf('► 추적 구간: 프레임 %d → %d  (총 %d 프레임)\n\n', t_start, t_end, Nf);

  % ★ 2-2. MP4 저장 여부 입력 --------------------------------------------
  ans_save = input('영상(mp4)으로 저장하시겠습니까? (y/n): ', 's');
  doSaveVideo = ~isempty(ans_save) && lower(ans_save(1)) == 'y';
  vw = [];   % VideoWriter 핸들 (저장 안 하면 빈 값 유지)
  if doSaveVideo
    fps_in = input('영상 프레임레이트(FPS)를 입력하세요 [기본 15]: ');
    if isempty(fps_in) || ~isnumeric(fps_in) || fps_in <= 0
      fps_in = 15;
    end
    [vname, vpath] = uiputfile('*.mp4', '저장할 영상 파일명 선택', 'streaklines.mp4');
    if isequal(vname, 0)
      doSaveVideo = false;
      fprintf('영상 저장이 취소되었습니다. 화면 출력만 진행합니다.\n');
    else
      vw = VideoWriter(fullfile(vpath, vname), 'MPEG-4');
      vw.FrameRate = fps_in;
      open(vw);
      fprintf('► 영상 저장: %s  (%.1f FPS)\n\n', fullfile(vpath, vname), fps_in);
    end
  end

  % 3. 주입점(시드) 선택 — 직선 2점 클릭 → 직선 위에 M개 등분 분포
  bg0 = imread(fileList{t_start});
  h0 = figure('Name', 'Select seed line', 'NumberTitle', 'off');
  imshow(bg0, 'InitialMagnification', 'fit');
  set(gca, 'XDir', 'normal', 'YDir', 'reverse'); axis image; hold on;

  title('주입선의 시작점과 끝점을 클릭하세요 (2회 클릭)', 'FontSize', 14);
  [x_line, y_line] = ginput(2);

  % 클릭한 직선 시각화 (노란 실선)
  plot(x_line, y_line, 'y-', 'LineWidth', 2);
  plot(x_line, y_line, 'ys', 'MarkerFaceColor', 'y', 'MarkerSize', 8);

  % 직선을 (M-1) 등분하여 M개의 균등 주입점 생성
  xs = linspace(x_line(1), x_line(2), M)';
  ys = linspace(y_line(1), y_line(2), M)';

  % 생성된 시드 점 시각화
  plot(xs, ys, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
  title(sprintf('주입점 %d개 균등 분포 완료', M), 'FontSize', 14);
  pause(1.0); close(h0);

  X = double(pivData.X);
  Y = double(pivData.Y);
  minX = min(X(:)); maxX = max(X(:));
  minY = min(Y(:)); maxY = max(Y(:));

  % 안전 마진 (시드가 그리드 밖이면 안쪽으로 보정)
  grid_res = max(abs(mean(diff(X(1,:)))), abs(mean(diff(Y(:,1)))));
  safe_margin = grid_res * 0.1;
  xs = max(min(xs, maxX - safe_margin), minX + safe_margin);
  ys = max(min(ys, maxY - safe_margin), minY + safe_margin);

  % 4. Streakline 추적 변수 초기화
  %    매 프레임 새 입자가 주입되므로 [주입점 M x 프레임 Nf] 공간이 필요
  posX = nan(M, Nf);
  posY = nan(M, Nf);

  % 각 개별 입자별 Coast Limit 상태 저장
  prev_u = zeros(M, Nf);
  prev_v = zeros(M, Nf);
  nan_coast_count = zeros(M, Nf);

  % 5. 시각화 준비
  hFig = figure('Name', 'Smart Streakline Tracking', 'Renderer', 'opengl');
  ax = axes('Parent', hFig); hold(ax, 'on');
  set(ax, 'YDir', 'reverse', 'XDir', 'normal', 'DataAspectRatio', [1 1 1]);
  hIm = imshow(bg0, 'Parent', ax, 'XData', [1 pivData.imSizeX], 'YData', [1 pivData.imSizeY]);

  cols = lines(M);
  hLines = gobjects(M, 1);
  hPoints = gobjects(M, 1);
  for i = 1:M
      % Streakline을 잇는 선 (가장 오래된 입자 → 최신 주입 입자)
      hLines(i) = plot(ax, NaN, NaN, '-', 'Color', cols(i,:), 'LineWidth', 1.5);
      % 각 입자의 현재 위치를 나타내는 마커
      hPoints(i) = plot(ax, NaN, NaN, '.', 'Color', cols(i,:), 'MarkerSize', 2);
  end

  % 6. Streakline 추적 연산 (★ fi: 구간 내부 인덱스, t: 실제 프레임 번호)
  for fi = 1:Nf
    t = t_start + fi - 1;     % 실제 프레임 인덱스로 변환

    % 배경 업데이트
    set(hIm, 'CData', imread(fileList{t}));

    % 6-1. 새 입자 주입 (현재 프레임 fi에 시드 위치에서 생성)
    posX(:, fi) = xs;
    posY(:, fi) = ys;

    % 6-2. 현재 활성화된 입자(1~fi)를 선으로 연결하여 그리기
    for i = 1:M
        set(hLines(i),  'XData', posX(i, 1:fi), 'YData', posY(i, 1:fi));
        set(hPoints(i), 'XData', posX(i, 1:fi), 'YData', posY(i, 1:fi));
    end
    title(ax, sprintf('Streakline Frame: %d / %d', t, t_end), 'FontSize', 14);
    drawnow;
    if ANIM_PAUSE > 0, pause(ANIM_PAUSE); end

    % ★ 영상 저장: 현재 화면을 한 프레임으로 기록
    if doSaveVideo
        writeVideo(vw, getframe(hFig));
    end

    % 마지막 프레임이면 이동 연산 없이 종료
    if fi == Nf
        break;
    end

    % 6-3. 다음 스텝을 위해 지금까지 주입된 전체 입자 이동
    U = double(pivData.U(:,:,t));
    V = double(pivData.V(:,:,t));

    for p = 1:fi   % p: 주입 시점(열) 인덱스 (1 ~ 현재 프레임)
      for i = 1:M
        x_curr = posX(i, p);
        y_curr = posY(i, p);

        u_val = interp2(X, Y, U, x_curr, y_curr, 'nearest');
        v_val = interp2(X, Y, V, x_curr, y_curr, 'nearest');

        % ★ 스마트 마스크 판별 (각 입자별 독립 적용) ★
        if isnan(u_val) || isnan(v_val)
            nan_coast_count(i, p) = nan_coast_count(i, p) + 1;

            if nan_coast_count(i, p) <= max_coast_frames
                % 관성 유지 (Coast Limit 적용 중) — 직전 속도로 미끄러짐
                u_val = prev_u(i, p);
                v_val = prev_v(i, p);
            else
                % 장애물/경계 판정 → 완전 정지
                u_val = 0;
                v_val = 0;
                prev_u(i, p) = 0;
                prev_v(i, p) = 0;
            end
        else
            % 정상 영역: 상태 초기화 및 속도 갱신
            nan_coast_count(i, p) = 0;
            prev_u(i, p) = u_val;
            prev_v(i, p) = v_val;
        end

        % 다음 위치 계산
        x_new = x_curr + u_val;
        y_new = y_curr + v_val;

        % 경계 제한
        posX(i, p) = max(min(x_new, maxX), minX);
        posY(i, p) = max(min(y_new, maxY), minY);
      end
    end
  end

  title(ax, 'Streakline 생성 완료 (Coast Limit & 장애물 정지 적용)', 'FontSize', 14);
  hold off;

  % ★ 영상 파일 닫기
  if doSaveVideo && ~isempty(vw)
    close(vw);
    fprintf('\n✔ 영상 저장 완료: %s\n', fullfile(vw.Path, vw.Filename));
  end

  % 출력 데이터 정리
  streaklines_data.posX    = posX;
  streaklines_data.posY    = posY;
  streaklines_data.t_start = t_start;
  streaklines_data.t_end   = t_end;
end
