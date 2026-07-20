function pivGridmove(pivData, fileList)
  %% 내부 재생 속도 (초)
  delay = 0.2;
  Nt    = pivData.Nt;
  nBg   = numel(fileList);

  %% 그리드 & 누적 변위 초기화
  X0   = pivData.X;
  Y0   = pivData.Y;
  Ucum = zeros(size(X0));
  Vcum = zeros(size(Y0));
  lineColors = {'g','r','c','y'};

  %% Figure + Axes 한 번만 생성
  hFig = figure('Renderer','opengl');
  ax   = axes('Parent',hFig);
  hold(ax,'on');
  set(ax,'YDir','reverse','XDir','normal','DataAspectRatio',[1 1 1]);

  % 1) 첫 프레임 배경 표시
  idx0 = min(1,nBg);
  bg0  = imread(fileList{idx0});
  hIm  = imshow(bg0, ...
         'Parent',ax, ...
         'XData',[1 pivData.imSizeX], ...
         'YData',[1 pivData.imSizeY], ...
         'InitialMagnification','fit');
  % ↓ 이걸 꼭 추가 ↓
  xlim(ax,[1 pivData.imSizeX]);
  ylim(ax,[1 pivData.imSizeY]);

  %% 이전에 그린 선들 핸들
  hLines = gobjects(0);

  %% 프레임 루프
  for t = 1:Nt
    % (a) 배경 교체
    idx = min(t, nBg);
    set(hIm,'CData', imread(fileList{idx}));

    % (b) 누적 변위 계산
    Ucum = Ucum + double(pivData.U(:,:,t));
    Vcum = Vcum + double(pivData.V(:,:,t));
    Xw   = X0 + Ucum;
    Yw   = Y0 + Vcum;

    % (c) 이전 선들 안전하게 삭제
    if ~isempty(hLines)
      valid = isgraphics(hLines);
      delete(hLines(valid));
      hLines = hLines(~valid);
    end

    % (d) 새 격자선 그리기
    [Ny,Nx] = size(Xw);
    for i = 1:Ny
      clr = lineColors{mod(i-1,4)+1};
      hLines(end+1) = plot(ax, Xw(i,:), Yw(i,:), 'Color',clr,'LineWidth',1); %#ok<AGROW>
    end
    for j = 1:Nx
      clr = lineColors{mod(j-1,4)+1};
      hLines(end+1) = plot(ax, Xw(:,j), Yw(:,j), 'Color',clr,'LineWidth',1); %#ok<AGROW>
    end

    % (e) 제목 갱신
    title(ax, sprintf('Frame %d / %d', t, Nt),'FontSize',14);

    drawnow; pause(delay);
    if ~ishandle(hFig), break; end
  end
end
