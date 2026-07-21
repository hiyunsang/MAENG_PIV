function trajectories = MAENG_Pathlines()
% MAENG_Pathlines — 가상 유동(inpaint_nans) 완전 제거, 100% Real Data 기반 추적
%                - 마스크 내부 입자: 삭제되지 않고 제자리에 점(Dot)으로 흔적 보존
%                - 정체 구간 입자: 주변 가상 유동에 휩쓸리지 않고 완벽히 정지
%                - ★ 맵(경계) 밖 이탈 입자: 그동안의 경로(선)는 그대로 남기되
%                                          현재 위치 포인트는 사라짐
%
%   ★ 추가 기능
%     - 점 개수 지정     : 코드 최상단 파라미터로 직접 입력
%     - 직선 시드 분포   : 직선 2점 클릭 → 직선 위에 점이 자동 등분 배치
%     - 프레임 범위 지정 : 시작/끝 프레임을 직접 입력하여 해당 구간만 추적
%     - MP4 영상 저장    : 실행 시 저장 여부(y/n)를 묻고, 원하면 MPEG-4로 기록

  %% ============================================================
  %  ★ 사용자 파라미터
  %% ============================================================
  M = 10;        % 직선 위에 분포시킬 점(시드)의 개수 (최소 2)
  %% ============================================================

  if M < 2
    warning('M=%d → 직선 위에 분포시키려면 최소 2개 필요. 자동으로 2로 설정.', M);
    M = 2;
  end

  % 1. pivData 가져오기
  if evalin('base','exist(''pivData'',''var'')')
    pivData = evalin('base','pivData');
  else
    error('Workspace에 pivData 변수가 없습니다.');
  end
  Nt = size(pivData.U, 3); 
  
  % 2. fileList 구성
  if evalin('base','exist(''fileList'',''var'')')
    fileList = evalin('base','fileList');
  elseif isfield(pivData,'imagePath')
    fld = pivData.imagePath;
    D = dir(fullfile(fld,'*.png'));
    if isempty(D), D = dir(fullfile(fld,'*.bmp')); end
    if isempty(D), error('pivData.imagePath에 이미지가 없습니다.'); end
    [~,idx] = sort({D.name});
    fileList = fullfile(fld,{D(idx).name});
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
  vw = [];        % VideoWriter 핸들 (저장 안 하면 빈 값 유지)
  vidSize = [];   % ★ 첫 프레임 해상도 저장용 (이후 프레임 크기를 여기에 맞춤)
  if doSaveVideo
    fps_in = input('영상 프레임레이트(FPS)를 입력하세요 [기본 15]: ');
    if isempty(fps_in) || ~isnumeric(fps_in) || fps_in <= 0
      fps_in = 15;
    end
    [vname, vpath] = uiputfile('*.mp4', '저장할 영상 파일명 선택', 'pathlines.mp4');
    if isequal(vname, 0)
      % 사용자가 저장 대화상자를 취소한 경우 → 저장 비활성화
      doSaveVideo = false;
      fprintf('영상 저장이 취소되었습니다. 화면 출력만 진행합니다.\n');
    else
      vw = VideoWriter(fullfile(vpath, vname), 'MPEG-4');
      vw.FrameRate = fps_in;
      vw.Quality   = 100;   % ★ 최대 화질 (0~100, MPEG-4는 100이 최고)
      open(vw);
      fprintf('► 영상 저장: %s  (%.1f FPS, Quality 100)\n\n', fullfile(vpath, vname), fps_in);
    end
  end
  
  % 3. 시드 선택 — 직선 2점 클릭 → 직선 위에 M개 등분 분포
  bg0 = imread(fileList{t_start});
  h0 = figure('Name','Select seed line','NumberTitle','off');
  imshow(bg0,'InitialMagnification','fit');
  set(gca,'XDir','normal','YDir','reverse'); axis image; hold on;

  title('직선의 시작점과 끝점을 클릭하세요 (2회 클릭)', 'FontSize', 14);
  [x_line, y_line] = ginput(2);

  % 클릭한 직선 시각화 (노란 실선)
  plot(x_line, y_line, 'y-', 'LineWidth', 2);
  plot(x_line, y_line, 'ys', 'MarkerFaceColor','y', 'MarkerSize', 8);

  % 직선을 (M-1) 등분하여 M개의 균등 점 생성
  xs = linspace(x_line(1), x_line(2), M)';
  ys = linspace(y_line(1), y_line(2), M)';

  % 생성된 시드 점 시각화
  plot(xs, ys, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 6);
  title(sprintf('Seed %d개 균등 분포 완료', M), 'FontSize', 14);
  pause(1.0); close(h0);
  
  X = double(pivData.X);  
  Y = double(pivData.Y);
  minX = min(X(:)); maxX = max(X(:));
  minY = min(Y(:)); maxY = max(Y(:));
  
  % 안전 마진
  grid_res = max(abs(mean(diff(X(1,:)))), abs(mean(diff(Y(:,1))))); 
  safe_margin = grid_res * 0.1;
  xs = max(min(xs, maxX - safe_margin), minX + safe_margin);
  ys = max(min(ys, maxY - safe_margin), minY + safe_margin);

  % ★ 로직 유지: 마스크 내부 시작점도 삭제하지 않고 모두 유지(흔적 보존)
  
  % 4. 추적 변수 초기화 (★ Nt → Nf 로 변경: 지정 구간만큼만 할당)
  trajectories = nan(M, Nf+1, 2);
  trajectories(:,1,1) = xs;
  trajectories(:,1,2) = ys;

  % ★ 입자 생존 상태 관리
  %    alive(i)     : true이면 아직 맵 안에서 추적 중, false면 경계 이탈로 종료
  %    death_idx(i) : 입자가 죽은 시점의 마지막 유효 경로 인덱스.
  %                   죽은 뒤에는 이 인덱스까지의 경로(선)만 고정해서 그린다.
  alive     = true(M, 1);
  death_idx = (Nf + 1) * ones(M, 1);   % 끝까지 살면 마지막 인덱스
  
  % 5. 시각화 준비
  %    ★ 영상 저장 시 화질 확보를 위해 figure 크기를 크고 일정하게 고정
  hFig = figure('Name', 'Real Data Pure Tracking', 'Renderer', 'opengl', ...
                'Color', 'w', 'Position', [100 100 1280 720]);
  ax = axes('Parent', hFig); hold(ax, 'on');
  set(ax, 'YDir', 'reverse', 'XDir', 'normal', 'DataAspectRatio', [1 1 1]);
  hIm = imshow(bg0, 'Parent', ax, 'XData', [1 pivData.imSizeX], 'YData', [1 pivData.imSizeY]);
  
  cols = lines(M);
  hLines = gobjects(M, 1);
  hPoints = gobjects(M, 1);
  for i = 1:M
      hLines(i) = plot(ax, NaN, NaN, '-', 'Color', cols(i,:), 'LineWidth', 1.5);
      % 흔적을 남겨줄 포인트 마커 생성
      hPoints(i) = plot(ax, trajectories(i,1,1), trajectories(i,1,2), 'o', ...
                        'Color', cols(i,:), 'MarkerFaceColor', cols(i,:), 'MarkerSize', 6);
  end
  
  % 탐색 각도를 최대 85도까지만 제한
  angles_deg = [];
  for a_idx = 5:5:85
      angles_deg = [angles_deg, a_idx, -a_idx]; %#ok<AGROW>
  end
  angles = [0, angles_deg * (pi/180)]; 
  
  % 6. 추적 연산 (★ fi: 구간 내부 인덱스(1~Nf), t: 실제 프레임 번호)
  for fi = 1:Nf
    t = t_start + fi - 1;     % 실제 프레임 인덱스로 변환

    set(hIm, 'CData', imread(fileList{t}));
      
    % ★ 로직 유지: inpaint_nans 미사용. 순수 오리지널 데이터만 사용
    U_orig = double(pivData.U(:,:,t));
    V_orig = double(pivData.V(:,:,t));
    
    for i = 1:M
      % ★ 이미 죽은(이탈) 입자는 더 이상 위치를 갱신하지 않음 (경로 NaN 유지)
      if ~alive(i)
          continue;
      end

      x_current = trajectories(i, fi, 1);
      y_current = trajectories(i, fi, 2);
      
      if isnan(x_current) || isnan(y_current), continue; end
      
      % 오리지널 데이터로부터 실제 이동 벡터 도출
      u_val = interp2(X, Y, U_orig, x_current, y_current, 'linear');
      v_val = interp2(X, Y, V_orig, x_current, y_current, 'linear');
      
      % 경계면에 있어 linear가 실패하면 nearest로 재시도
      if isnan(u_val) || isnan(v_val)
          u_val = interp2(X, Y, U_orig, x_current, y_current, 'nearest');
          v_val = interp2(X, Y, V_orig, x_current, y_current, 'nearest');
      end
      
      % ★ 정체 구간: 마스크 내부 깊숙이 있거나 속도가 완전히 0인 경우
      if isnan(u_val) || isnan(v_val) || (u_val == 0 && v_val == 0)
          % 이동하지 않고 제자리 대기 -> 화면에 점(흔적)으로 남게 됨
          trajectories(i, fi+1, 1) = x_current;
          trajectories(i, fi+1, 2) = y_current;
          continue; 
      end 
      
      x_next = x_current + u_val;
      y_next = y_current + v_val;
      
      % ★ 경계 밖으로 나가려는 경우: 입자 종료(dead) 처리
      %    - trajectories(i, fi+1, :)는 NaN인 채로 둠 → 현재 위치 포인트가 사라짐
      %    - death_idx(i) = fi 로 기록 → 이탈 직전(fi)까지의 경로(선)만 고정 표시
      if x_next <= minX || x_next >= maxX || y_next <= minY || y_next >= maxY
          alive(i)     = false;
          death_idx(i) = fi;        % 마지막 유효 경로 인덱스
          continue; 
      end
      
      % 다음 스텝이 마스크(NaN) 영역인지 확인
      check_dest = interp2(X, Y, U_orig, x_next, y_next, 'nearest');
      
      % 장애물 회피 (자신의 원래 속도 관성만을 이용해 미끄러짐 각도 탐색)
      if isnan(check_dest)
          speed = norm([u_val, v_val]); 
          moved = false;
          
          if speed > 0
              ang_orig = atan2(v_val, u_val);
              
              for ang_offset = angles
                  ang_test = ang_orig + ang_offset;
                  speed_proj = speed * cos(ang_offset); 
                  
                  x_test = x_current + cos(ang_test) * speed_proj;
                  y_test = y_current + sin(ang_test) * speed_proj;
                  
                  val_test = interp2(X, Y, U_orig, x_test, y_test, 'nearest');
                  
                  if ~isnan(val_test)
                      x_next = x_test;
                      y_next = y_test;
                      moved = true;
                      break; 
                  end
              end
          end
          
          if ~moved
              x_next = x_current;
              y_next = y_current;
          end
      end
      
      trajectories(i, fi+1, 1) = x_next;
      trajectories(i, fi+1, 2) = y_next;
    end
    
    % 애니메이션 렌더링 (★ 인덱싱을 fi 기준으로 변경)
    for i = 1:M
        if alive(i)
            % 살아있는 입자: 경로(선) + 현재 위치 포인트 모두 표시
            set(hLines(i),  'XData', trajectories(i, 1:fi+1, 1), ...
                            'YData', trajectories(i, 1:fi+1, 2));
            set(hPoints(i), 'XData', trajectories(i, fi+1, 1), ...
                            'YData', trajectories(i, fi+1, 2));
        else
            % ★ 죽은(이탈) 입자: 이탈 직전까지의 경로(선)만 고정 표시,
            %    현재 위치 포인트는 NaN으로 두어 화면에서 사라지게 함
            di = death_idx(i);
            set(hLines(i),  'XData', trajectories(i, 1:di, 1), ...
                            'YData', trajectories(i, 1:di, 2));
            set(hPoints(i), 'XData', NaN, 'YData', NaN);
        end
    end
    title(ax, sprintf('Tracking Frame: %d / %d', t, t_end), 'FontSize', 14);
    drawnow; 

    % ★ 영상 저장: 현재 figure를 고해상도(150 DPI)로 캡처하여 기록
    if doSaveVideo
        frameImg = print(hFig, '-RGBImage', '-r150');   % 화면 종속성 없이 고해상도 렌더
        if isempty(vidSize)
            vidSize = [size(frameImg,1), size(frameImg,2)];   % 첫 프레임 크기 기준 고정
        else
            % VideoWriter는 모든 프레임 크기가 동일해야 하므로 첫 프레임 크기에 맞춤
            if size(frameImg,1) ~= vidSize(1) || size(frameImg,2) ~= vidSize(2)
                frameImg = imresize(frameImg, vidSize);
            end
        end
        writeVideo(vw, frameImg);
    end
  end

  % ★ 영상 파일 닫기
  if doSaveVideo && ~isempty(vw)
    close(vw);
    fprintf('\n✔ 영상 저장 완료: %s\n', fullfile(vw.Path, vw.Filename));
  end
end
