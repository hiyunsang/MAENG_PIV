function trajectories = MAENG_PathlinesArrow()
% MAENG_PathlinesArrow — 굵고 반투명한 화살표형 경로선으로 입자 이동 방향 시각화
%
%   기능:
%     - 프레임 범위 : 시작/끝 프레임을 직접 지정 가능
%     - Seed 입력   : 직선 2점 클릭 → 직선 위에 M개 균등 분포
%     - 경로선(Trail) : 굵고 반투명한 선
%     - 화살촉(Head)  : 현재 위치에 이동 방향을 향하는 삼각형 patch
%     - 꼬리 길이     : 최근 TAIL_LEN 프레임만 선으로 유지 (0 = 전체 보존)
%     - 마스크 내부   : 제자리 점(Dot)으로 흔적 보존, 가상 유동 불사용
%     - ★ 맵 밖으로 나간 입자: 화살표 + 이후 궤적 모두 사라짐
%     - ★ 맵 안에서 정지한 입자: 직전 이동 방향으로 화살표 유지
%
%   MATLAB R2019b 이상 필요 (4원소 Color [R G B alpha] 지원)

  %% ============================================================
  %  ★ 사용자 파라미터
  %% ============================================================
  LINE_WIDTH  = 5;      % 선 굵기 (픽셀)
  LINE_ALPHA  = 0.60;   % 선 투명도 (0=완전투명 ~ 1=불투명)
  ARROW_SIZE  = 14;     % 화살촉 길이 (이미지 픽셀 단위)
  ARROW_WIDTH = 0.45;   % 화살촉 너비 = ARROW_SIZE * ARROW_WIDTH
  ARROW_ALPHA = 0.90;   % 화살촉 투명도
  TAIL_LEN    = 0;      % 꼬리 보존 프레임 수 (0 = 전체 프레임 유지)
  %% ============================================================

  %% 1. pivData 가져오기
  if evalin('base','exist(''pivData'',''var'')')
    pivData = evalin('base','pivData');
  else
    error('Workspace에 pivData 변수가 없습니다.');
  end
  Nt = size(pivData.U, 3);

  %% 2. fileList 구성
  if evalin('base','exist(''fileList'',''var'')')
    fileList = evalin('base','fileList');
  elseif isfield(pivData,'imagePath')
    fld = pivData.imagePath;
    D = dir(fullfile(fld,'*.png'));
    if isempty(D), D = dir(fullfile(fld,'*.bmp')); end
    if isempty(D), error('pivData.imagePath에 이미지가 없습니다.'); end
    [~,idx] = sort({D.name});
    fileList = fullfile(fld, {D(idx).name});
  else
    error('Workspace에 fileList가 없고, pivData.imagePath도 정의되지 않았습니다.');
  end

  if numel(fileList) < Nt
    error('fileList 개수(%d) < Nt(%d).', numel(fileList), Nt);
  elseif numel(fileList) > Nt
    fileList = fileList(1:Nt);
  end

  %% 3. 프레임 범위 입력
  fprintf('\n전체 프레임 수: %d\n', Nt);
  t_start = input(sprintf('시작 프레임 입력 (1 ~ %d): ', Nt));
  t_end   = input(sprintf('끝   프레임 입력 (%d ~ %d): ', t_start, Nt));

  t_start = max(1,       min(round(t_start), Nt));
  t_end   = max(t_start, min(round(t_end),   Nt));
  Nf      = t_end - t_start + 1;

  fprintf('► 추적 구간: 프레임 %d → %d  (총 %d 프레임)\n\n', t_start, t_end, Nf);

  %% 4. ★ Seed 직선 입력 — 직선 위에 균등 분포
  bg0 = imread(fileList{t_start});
  h0  = figure('Name','Seed 직선 입력','NumberTitle','off');
  imshow(bg0,'InitialMagnification','fit');
  set(gca,'XDir','normal','YDir','reverse');
  axis image; hold on;

  M = input('직선 위에 몇 개의 점을 분포시키겠습니까? (숫자 입력 후 Enter): ');
  if M < 2
    warning('M=%d → 직선 위에 분포시키려면 최소 2개 필요. 자동으로 2로 설정.', M);
    M = 2;
  end

  title('직선의 시작점과 끝점을 클릭하세요 (2회 클릭)', 'FontSize', 14);
  [x_line, y_line] = ginput(2);

  % 클릭한 직선 시각화 (노란 실선)
  plot(x_line, y_line, 'y-',  'LineWidth', 2);
  plot(x_line, y_line, 'ys',  'MarkerFaceColor','y', 'MarkerSize', 8);

  % 직선을 (M-1) 등분하여 M개의 균등 점 생성
  xs = linspace(x_line(1), x_line(2), M)';
  ys = linspace(y_line(1), y_line(2), M)';

  % 생성된 Seed 점 시각화
  plot(xs, ys, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 6);
  title(sprintf('Seed %d개 균등 분포 완료', M), 'FontSize', 14);
  pause(1.0); close(h0);

  %% 5. 그리드 경계 및 안전 마진 — Seed가 PIV 그리드 밖이면 안쪽으로 보정
  X = double(pivData.X);
  Y = double(pivData.Y);
  minX = min(X(:));  maxX = max(X(:));
  minY = min(Y(:));  maxY = max(Y(:));

  grid_res    = max(abs(mean(diff(X(1,:)))), abs(mean(diff(Y(:,1)))));
  safe_margin = grid_res * 0.1;
  xs = max(min(xs, maxX - safe_margin), minX + safe_margin);
  ys = max(min(ys, maxY - safe_margin), minY + safe_margin);

  %% 6. 추적 변수 초기화 (M x Nf+1 x 2)
  trajectories = nan(M, Nf+1, 2);
  trajectories(:, 1, 1) = xs;
  trajectories(:, 1, 2) = ys;

  %% 7. 그래픽 오브젝트 초기화
  hFig = figure('Name', sprintf('Arrow Pathlines  [Frame %d ~ %d]', t_start, t_end), ...
                'Renderer','opengl');
  ax = axes('Parent', hFig);
  hold(ax,'on');
  set(ax, 'YDir','reverse', 'XDir','normal', 'DataAspectRatio',[1 1 1]);

  hIm = imshow(bg0, 'Parent', ax, ...
               'XData',[1 pivData.imSizeX], ...
               'YData',[1 pivData.imSizeY]);

  cols    = lines(M);
  hLines  = gobjects(M, 1);
  hArrows = gobjects(M, 1);

  for i = 1:M
    hLines(i) = plot(ax, NaN, NaN, '-', ...
                     'Color',     [cols(i,:), LINE_ALPHA], ...
                     'LineWidth', LINE_WIDTH);
    hArrows(i) = patch(ax, ...
                       'XData',     [NaN NaN NaN], ...
                       'YData',     [NaN NaN NaN], ...
                       'FaceColor', cols(i,:), ...
                       'EdgeColor', 'none', ...
                       'FaceAlpha', ARROW_ALPHA);
  end

  %% 8. 장애물 우회 탐색 각도 (-85° ~ +85°, 5° 간격)
  angles_deg = [];
  for a_idx = 5:5:85
    angles_deg = [angles_deg, a_idx, -a_idx]; %#ok<AGROW>
  end
  angles = [0, angles_deg * (pi/180)];

  %% 9. 프레임별 추적 & 렌더링
  for fi = 1:Nf
    t = t_start + fi - 1;

    set(hIm, 'CData', imread(fileList{t}));

    U_orig = double(pivData.U(:,:,t));
    V_orig = double(pivData.V(:,:,t));

    % ── 입자별 이동 계산 ──
    for i = 1:M
      xc = trajectories(i, fi, 1);
      yc = trajectories(i, fi, 2);

      % 이미 사라진 입자(NaN)는 계속 NaN 유지
      if isnan(xc) || isnan(yc)
        trajectories(i, fi+1, 1) = NaN;
        trajectories(i, fi+1, 2) = NaN;
        continue;
      end

      u = interp2(X, Y, U_orig, xc, yc, 'linear');
      v = interp2(X, Y, V_orig, xc, yc, 'linear');
      if isnan(u) || isnan(v)
        u = interp2(X, Y, U_orig, xc, yc, 'nearest');
        v = interp2(X, Y, V_orig, xc, yc, 'nearest');
      end

      % 속도가 없거나 0 → 제자리 정지 (입자 보존, 화살표는 직전 방향 유지)
      if isnan(u) || isnan(v) || (u == 0 && v == 0)
        trajectories(i, fi+1, 1) = xc;
        trajectories(i, fi+1, 2) = yc;
        continue;
      end

      xn = xc + u;
      yn = yc + v;

      % ★ 맵(그리드) 밖으로 나가면 입자 소멸 → NaN
      if xn<=minX || xn>=maxX || yn<=minY || yn>=maxY
        trajectories(i, fi+1, 1) = NaN;
        trajectories(i, fi+1, 2) = NaN;
        continue;
      end

      % 마스크(NaN 영역) 진입 시 우회 시도
      if isnan(interp2(X, Y, U_orig, xn, yn, 'nearest'))
        spd   = norm([u, v]);
        moved = false;
        if spd > 0
          ang0 = atan2(v, u);
          for dang = angles
            a_test  = ang0 + dang;
            sp_proj = spd * cos(dang);
            xt = xc + cos(a_test)*sp_proj;
            yt = yc + sin(a_test)*sp_proj;
            if ~isnan(interp2(X, Y, U_orig, xt, yt, 'nearest'))
              xn = xt;  yn = yt;
              moved = true;
              break;
            end
          end
        end
        % 우회 실패 → 제자리 정지 (입자 보존)
        if ~moved, xn = xc; yn = yc; end
      end

      trajectories(i, fi+1, 1) = xn;
      trajectories(i, fi+1, 2) = yn;
    end

    % ── 렌더링 ──
    for i = 1:M
      if TAIL_LEN > 0
        fi_start = max(1, fi+1 - TAIL_LEN);
      else
        fi_start = 1;
      end
      xdata = squeeze(trajectories(i, fi_start:fi+1, 1))';
      ydata = squeeze(trajectories(i, fi_start:fi+1, 2))';

      % 선 그리기 (NaN은 자동으로 끊어짐 → 소멸 이후 구간은 그려지지 않음)
      set(hLines(i), 'XData', xdata, 'YData', ydata);

      % ★ 현재 프레임 위치가 NaN이면(= 맵 밖으로 나가서 소멸) 화살표 숨김
      xc_now = trajectories(i, fi+1, 1);
      yc_now = trajectories(i, fi+1, 2);
      if isnan(xc_now) || isnan(yc_now)
        set(hArrows(i), 'XData',[NaN NaN NaN], 'YData',[NaN NaN NaN]);
        continue;
      end

      % ★ 방향 탐색은 전체 궤적(1:fi+1) 기준 — 꼬리 길이와 무관하게 최근 이동 방향 확보
      xall = squeeze(trajectories(i, 1:fi+1, 1))';
      yall = squeeze(trajectories(i, 1:fi+1, 2))';
      vi   = find(~isnan(xall) & ~isnan(yall));

      if numel(vi) >= 2
        % 화살촉 기준점 = 현재(마지막 valid) 위치
        x_tip = xall(vi(end));
        y_tip = yall(vi(end));

        % ★ 가장 최근 "실제 이동이 있었던" 구간의 방향을 사용
        %   (마스크/속도 0 등으로 정지해도 직전 이동 방향 유지)
        ang = NaN;
        for k = numel(vi):-1:2
          dxk = xall(vi(k)) - xall(vi(k-1));
          dyk = yall(vi(k)) - yall(vi(k-1));
          if dxk ~= 0 || dyk ~= 0
            ang = atan2(dyk, dxk);
            break;
          end
        end

        % 한 번도 움직이지 않은 입자만 화살표 숨김
        if isnan(ang)
          set(hArrows(i), 'XData',[NaN NaN NaN], 'YData',[NaN NaN NaN]);
          continue;
        end

        AL  = ARROW_SIZE;
        AW  = AL * ARROW_WIDTH;

        tip_x  = x_tip + cos(ang)*(AL*0.5);
        tip_y  = y_tip + sin(ang)*(AL*0.5);
        left_x = x_tip - cos(ang)*AL + sin(ang)*AW;
        left_y = y_tip - sin(ang)*AL - cos(ang)*AW;
        rght_x = x_tip - cos(ang)*AL - sin(ang)*AW;
        rght_y = y_tip - sin(ang)*AL + cos(ang)*AW;

        set(hArrows(i), ...
            'XData', [tip_x, left_x, rght_x], ...
            'YData', [tip_y, left_y, rght_y]);
      end
    end

    title(ax, sprintf('Arrow Pathlines  |  Frame: %d / %d  (구간: %d ~ %d)', ...
                      t, t_end, t_start, t_end), 'FontSize', 14);
    drawnow;
  end
end