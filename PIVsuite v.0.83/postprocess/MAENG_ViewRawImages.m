function MAENG_ViewRawImages(rawFolder, delay)
% MAENG_ViewRawImages  —  지정 폴더의 Img000001.bmp 부터 Img000040.bmp 까지
%                  원본 이미지만 풀스크린으로 순차 재생
%
% MAENG_ViewRawImages(rawFolder)  
% MAENG_ViewRawImages(rawFolder, delay)
%
% Inputs:
%   rawFolder : 원본 BMP 파일들이 있는 폴더 경로 (예: '../Data/Test Tububu')
%   delay     : (optional) 프레임 간 재생 간격 [초], 기본 0.2

  if nargin<2 || isempty(delay)
    delay = 0.2;
  end

  % 풀스크린 Figure
  hFig = figure('Units','normalized', ...
                'OuterPosition',[0 0 1 1], ...
                'MenuBar','none', ...
                'ToolBar','none');

  for k = 1:40
    % 파일 이름
    fname = fullfile(rawFolder, sprintf('Img%06d.bmp', k));
    if ~exist(fname,'file')
      warning('파일이 없습니다: %s', fname);
      continue;
    end

    % 이미지 읽기
    I = imread(fname);

    % 화면 갱신
    clf(hFig);
    imshow(I, ...
           'InitialMagnification','fit', ...
           'Border','tight');
    title(sprintf('%02d / 40: %s', k, fname), ...
          'Interpreter','none','FontSize',16);
    drawnow;

    pause(delay);
    if ~ishandle(hFig), 
      break;  % 창 닫으면 종료
    end
  end
end