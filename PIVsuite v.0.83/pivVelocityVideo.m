function pivVelocityVideo()
% pivVelocityVideo — 시퀀스 PIV 속도장을 MP4(MPEG-4) 영상으로 출력
% -------------------------------------------------------------------------
% [기능]
%   - visualizePairFromSequence 의 비주얼(turbo 컬러맵 + 마스크 경계 +
%     자유면/공구 영역 grayscale 배경 합성)을 "전 프레임"에 대해 반복 렌더링하여
%     MPEG-4 영상으로 저장한다.
%   - 각 프레임에 프레임 번호(Frame k / Nt)를 좌상단 스탬프 + 제목 양쪽에 항상 표시.
%   - F5 실행: base workspace 의 pivData(시퀀스)를 자동 로드하므로 인자 불필요.
%   - 다이얼로그 없음(완전 자동). 아래 "사용자 입력부"만 수정하면 된다.
%
% [입력 소스 우선순위]
%   마스크 : maskPathManual > pivData.imMaskArray1 > pivData.imMaskFilename1
%   배경   : pivData.imArray1 > pivData.imFilename1
%            > base workspace 의 fileList > (imgFolderManual | pivData.imagePath) 폴더 스캔
%   ※ 마스크가 전혀 없으면 자동으로 "마스크 없이(전체 컬러 속도장)" 모드로 진행.
%
% [출력]
%   videoName 으로 지정한 .mp4 (MPEG-4 미지원 환경이면 .avi(Motion JPEG)로 자동 대체)
% -------------------------------------------------------------------------

%% ===== 사용자 입력부 (여기만 수정) =====
fps          = 40000;        % 촬영 frame rate [frame/sec]  (속도 단위 환산용)
pixelSize    = 0.00234;     % 광학계 보정값 [mm/px]
colorMax     = 30;           % 컬러바 상한 [m/min]
colorMin     = 0;           % 컬러바 하한 [m/min]
bgBrightness = 1.1;         % 배경 이미지 밝기 보정 (1.0 = 원본)
bgContrast   = 1.2;         % 배경 이미지 대비   (1.0 = 원본)
useMask      = true;        % true: 마스크 합성, false: 전체 컬러 속도장(마스크 무시)
showBoundary = true;        % true: 마스크 경계선(검정) 표시

frameStart   = 1;           % 시작 프레임 (1 이상)
frameEnd     = inf;         % 끝 프레임   (inf = 마지막 프레임까지)
frameStep    = 1;           % 프레임 간격 (1 = 전부, 2 = 한 칸씩 건너뜀: 빠른 미리보기용)

playbackFPS  = 15;          % ★ 출력 영상의 재생 속도 [frame/sec] (촬영 fps 와 무관)
videoName    = 'pivVelocity_video.mp4';   % 저장 파일명
figPixW      = 1000;        % 렌더 figure 가로 [px]
figPixH      = 860;         % 렌더 figure 세로 [px]

maskPathManual  = '';       % (선택) 단일 마스크 파일 경로 수동 지정
imgFolderManual = '';       % (선택) 배경 이미지 폴더 수동 지정 (정렬 후 k번째 사용)
% =========================================

%% 1. pivData 로드 및 검증
if evalin('base','exist(''pivData'',''var'')')
    pivData = evalin('base','pivData');
else
    error('Workspace에 pivData 변수가 없습니다. 시퀀스 분석을 먼저 수행하세요.');
end
if ~isfield(pivData,'U') || size(pivData.U,3) < 2
    error('시퀀스 PIV 결과가 아닙니다 (size(pivData.U,3) >= 2 필요).');
end
Nt = size(pivData.U,3);

% 배경 fallback: base workspace 의 fileList (pivPathlines 와 동일 관례)
if evalin('base','exist(''fileList'',''var'')')
    fileList = evalin('base','fileList');
else
    fileList = {};
end

% 배경 fallback: 폴더 스캔 목록 (imgFolderManual 또는 pivData.imagePath)
folderList = {};
if ~isempty(imgFolderManual) && isfolder(imgFolderManual)
    folderList = scanImages(imgFolderManual);
elseif isfield(pivData,'imagePath') && ischar(pivData.imagePath) && isfolder(pivData.imagePath)
    folderList = scanImages(pivData.imagePath);
end

%% 2. 프레임 범위 결정
fStart = max(1, round(frameStart));
fEnd   = min(round(frameEnd), Nt);
frameVec = fStart:max(1,round(frameStep)):fEnd;
if isempty(frameVec)
    error('유효한 프레임 범위가 없습니다 (start=%d, end=%d, step=%d).', ...
          fStart, fEnd, frameStep);
end
fprintf('\n>>> MP4 영상 생성: 프레임 %d ~ %d (step %d) / 총 %d 장\n', ...
        frameVec(1), frameVec(end), max(1,round(frameStep)), numel(frameVec));

%% 3. 이미지 크기 결정 (첫 프레임 기준)
imH = []; imW = [];
mb0 = resolveMaskFrame(pivData, frameVec(1), maskPathManual);
if ~isempty(mb0)
    [imH, imW] = size(mb0);
end
if isempty(imH)
    bg0 = resolveBgFrame(pivData, frameVec(1), fileList, folderList);
    if ~isempty(bg0), [imH, imW] = size(bg0(:,:,1)); end
end
if isempty(imH) && isfield(pivData,'imSizeY') && isfield(pivData,'imSizeX')
    imH = double(pivData.imSizeY);   imW = double(pivData.imSizeX);
end
if isempty(imH)
    error('이미지 크기를 결정할 수 없습니다 (마스크/배경/imSize 중 하나 필요).');
end
fprintf('  화면 해상도: %d(W) x %d(H) px\n', imW, imH);

%% 4. 전 프레임 공통 준비 (그리드 / 단위환산 계수)
X = double(pivData.X);   Y = double(pivData.Y);
xGrid = X(1,:);          % PIV 그리드 x-좌표 (행벡터)  ※ 원본과 동일
yGrid = Y(:,1);          % PIV 그리드 y-좌표 (열벡터)
[Xpix, Ypix] = meshgrid(1:imW, 1:imH);     % 픽셀 좌표 그리드
convFactor = pixelSize * fps * 0.06;       % px/frame -> m/min
denom = max(colorMax - colorMin, eps);     % 0-나눗셈 방지

%% 5. turbo 컬러맵 정의 (R2020b 미만 호환)
nColors = 256;
try
    cmap = turbo(nColors);                  % R2020b+ 내장
catch
    keyC = [ 0.18995, 0.07176, 0.23217;     % deep purple
             0.27149, 0.41614, 0.81616;     % blue
             0.13990, 0.71880, 0.84314;     % cyan-blue
             0.16444, 0.89409, 0.55834;     % green-cyan
             0.71776, 0.95977, 0.20755;     % yellow-green
             0.97819, 0.79410, 0.20194;     % yellow-orange
             0.95201, 0.36915, 0.10882;     % orange-red
             0.47960, 0.01583, 0.01055];    % dark red
    ts = linspace(0,1,size(keyC,1)).';
    tq = linspace(0,1,nColors).';
    cmap = [interp1(ts,keyC(:,1),tq,'pchip'), ...
            interp1(ts,keyC(:,2),tq,'pchip'), ...
            interp1(ts,keyC(:,3),tq,'pchip')];
    cmap = max(0,min(1,cmap));
end

%% 6. Figure / 축 / 컬러바 / 스탬프 1회 구성 (루프에서는 갱신만)
hFig = figure(101); clf(hFig);
set(hFig,'Color','w','Units','pixels','Position',[80 80 figPixW figPixH], ...
         'Name','PIV Velocity Video','NumberTitle','off','MenuBar','none');
tl = tiledlayout(hFig,1,1,'Padding','compact','TileSpacing','compact');
ax = nexttile(tl);

hImg = image(ax,[1 imW],[1 imH], zeros(imH,imW,3));   % 빈 RGB 로 생성
colormap(ax, cmap);
try, clim(ax,[colorMin colorMax]); catch, caxis(ax,[colorMin colorMax]); end %#ok<CAXIS>

axis(ax,'image');  axis(ax,[1 imW 1 imH]);
set(ax,'YDir','reverse','FontName','Arial','FontSize',11, ...
       'LineWidth',1.2,'TickDir','out','Box','on','Layer','top');
xlabel(ax,'x [px]','FontSize',12,'FontName','Arial');
ylabel(ax,'y [px]','FontSize',12,'FontName','Arial');
hTitle = title(ax,'','FontWeight','normal','FontSize',12, ...
               'Interpreter','tex','FontName','Arial');

cb = colorbar(ax,'Location','southoutside');
cb.Label.String = 'Material velocity v_m  [m/min]';
cb.Label.FontSize = 12;  cb.Label.FontName = 'Arial';
cb.FontSize = 10;  cb.FontName = 'Arial';
cb.LineWidth = 1.0;  cb.TickDirection = 'out';
cb.Ticks = linspace(colorMin,colorMax,5);
rng = colorMax - colorMin;
if rng >= 10,    fmt = '%.0f';
elseif rng >= 1, fmt = '%.2f';
else,            fmt = '%.3f'; end
cb.TickLabels = arrayfun(@(v) sprintf(fmt,v), cb.Ticks,'UniformOutput',false);

% 프레임 번호 스탬프 (좌상단, 검정 박스 + 흰 글씨 → 어떤 배경에서도 가독)
hold(ax,'on');
hStamp = text(ax, 0.015, 0.985, '', 'Units','normalized', ...
    'HorizontalAlignment','left','VerticalAlignment','top', ...
    'FontName','Arial','FontSize',13,'FontWeight','bold', ...
    'Color','w','BackgroundColor','k','Margin',4);
hold(ax,'off');

hBoundary = gobjects(0);   % 경계선 핸들 (프레임마다 삭제 후 재생성)

%% 7. VideoWriter 준비 (MPEG-4, 실패 시 AVI 자동 대체)
try
    vidObj = VideoWriter(videoName,'MPEG-4');
catch
    [p,n,~] = fileparts(videoName);
    videoName = fullfile(p,[n '.avi']);
    vidObj = VideoWriter(videoName,'Motion JPEG AVI');
    warning('MPEG-4 사용 불가 → AVI(Motion JPEG)로 저장합니다: %s', videoName);
end
vidObj.FrameRate = max(1, round(playbackFPS));
try, vidObj.Quality = 100; catch, end      % Quality 미지원 프로파일 보호
open(vidObj);

fixedH = [];  fixedW = [];                 % 첫 캡처 크기로 모든 프레임 통일
warnedNoMask = false;
nLoop = numel(frameVec);

%% 8. 프레임 루프
for ii = 1:nLoop
    k = frameVec(ii);

    % --- (a) 마스크 ---
    if useMask
        maskBin = resolveMaskFrame(pivData, k, maskPathManual);
        if isempty(maskBin)
            maskBin = true(imH,imW);
            if ~warnedNoMask
                warning('마스크를 찾지 못해 "마스크 없이(전체 컬러)"로 진행합니다.');
                warnedNoMask = true;
            end
        elseif ~isequal(size(maskBin),[imH imW])
            maskBin = imresize(maskBin,[imH imW],'nearest');
        end
    else
        maskBin = true(imH,imW);
    end

    % --- (b) 배경 (마스크 합성 모드에서만 필요) ---
    if useMask
        bgRaw = resolveBgFrame(pivData, k, fileList, folderList);
        if isempty(bgRaw)
            bgImg = zeros(imH,imW) + 0.78;          % 배경 없으면 회색
        else
            if size(bgRaw,3) > 1, bgRaw = rgb2gray(bgRaw); end
            bgImg = double(bgRaw);
            if ~isequal(size(bgImg),[imH imW]), bgImg = imresize(bgImg,[imH imW]); end
            bgImg = bgImg / max(bgImg(:));
            bgImg = (bgImg - 0.5)*bgContrast + 0.5;
            bgImg = bgImg * bgBrightness;
            bgImg = max(0,min(1,bgImg));
        end
    else
        bgImg = zeros(imH,imW);                     % 전체 컬러 모드 → 미사용
    end

    % --- (c) 속도장 추출 + 단위 환산 ---
    pair   = pivManipulateData('readTimeSlice', pivData, k);
    U_phys = pair.U * convFactor;
    V_phys = pair.V * convFactor;

    % --- (d) NaN 외삽 ---
    if any(isnan(U_phys(:)))
        U_fill = inpaint_nans(U_phys,2);
        V_fill = inpaint_nans(V_phys,2);
    else
        U_fill = U_phys;   V_fill = V_phys;
    end

    % --- (e) 픽셀 해상도 업샘플링 ---
    F_U   = griddedInterpolant({yGrid,xGrid}, U_fill, 'cubic','linear');
    F_V   = griddedInterpolant({yGrid,xGrid}, V_fill, 'cubic','linear');
    U_pix = F_U(Ypix,Xpix);
    V_pix = F_V(Ypix,Xpix);
    Umag  = sqrt(U_pix.^2 + V_pix.^2);

    % --- (f) RGB 합성 (색=속도장 / 회색=배경) ---
    Un   = max(0, min(1, (Umag - colorMin)/denom));
    cIdx = max(1, min(nColors, round(Un*(nColors-1)) + 1));
    vR   = reshape(cmap(cIdx(:),1), imH, imW);
    vG   = reshape(cmap(cIdx(:),2), imH, imW);
    vB   = reshape(cmap(cIdx(:),3), imH, imW);
    rgb  = zeros(imH,imW,3);
    rgb(:,:,1) = vR.*maskBin + bgImg.*(~maskBin);
    rgb(:,:,2) = vG.*maskBin + bgImg.*(~maskBin);
    rgb(:,:,3) = vB.*maskBin + bgImg.*(~maskBin);
    rgb = max(0, min(1, rgb));

    % --- (g) 화면 갱신 (image / 제목 / 프레임 스탬프) ---
    set(hImg,'CData',rgb);
    set(hTitle,'String', sprintf('Velocity Field — Pair #%d (image %d \\rightarrow %d)', k, k, k+1));
    set(hStamp,'String', sprintf('Frame %d / %d', k, Nt));

    % --- 경계선 갱신 (프레임마다 형상이 변하므로 삭제 후 재생성) ---
    if ~isempty(hBoundary), delete(hBoundary(isgraphics(hBoundary))); end
    hBoundary = gobjects(0);
    if showBoundary && useMask && any(~maskBin(:)) && any(maskBin(:))
        hold(ax,'on');
        B  = bwboundaries(maskBin, 8, 'noholes');
        hB = gobjects(numel(B),1);
        for kk = 1:numel(B)
            bd = B{kk};
            hB(kk) = plot(ax, bd(:,2), bd(:,1), 'k-', 'LineWidth', 1.5);
        end
        hold(ax,'off');
        hBoundary = hB;
    end

    drawnow;

    % --- (h) 프레임 캡처 → 영상 기록 (크기 일관성 강제) ---
    fr  = getframe(hFig);
    img = fr.cdata;
    if isempty(fixedH)
        fixedH = size(img,1) - mod(size(img,1),2);   % MPEG-4 안정성 위해 짝수
        fixedW = size(img,2) - mod(size(img,2),2);
    end
    if size(img,1) ~= fixedH || size(img,2) ~= fixedW
        img = imresize(img,[fixedH fixedW]);
    end
    writeVideo(vidObj, img);

    % --- (i) 진행 표시 ---
    if mod(ii,25)==0 || ii==nLoop
        fprintf('  [%d/%d] frame %d 기록 완료\n', ii, nLoop, k);
    end
end

%% 9. 마무리
close(vidObj);
fprintf('\n[완료] 영상 저장: %s\n', videoName);
fprintf('       %d 프레임 / 재생 %d fps / 해상도 %d x %d px\n', ...
        nLoop, vidObj.FrameRate, fixedW, fixedH);
% figure 는 마지막 프레임 상태로 유지(확인용)
end


% ========================================================================
%                            보조 함수
% ========================================================================
function maskBin = resolveMaskFrame(pivData, k, maskPathManual)
% 프레임 k의 마스크를 logical(HxW)로 반환. 없으면 [] 반환.
    maskImg = [];
    % (1) 수동 경로
    if isempty(maskImg) && ~isempty(maskPathManual) && exist(maskPathManual,'file')
        maskImg = imread(maskPathManual);
    end
    % (2) 배열 (pivData.imMaskArray1)
    if isempty(maskImg) && isfield(pivData,'imMaskArray1') && ~isempty(pivData.imMaskArray1)
        arr = pivData.imMaskArray1;
        if ndims(arr)==3 && size(arr,3)>=k, maskImg = arr(:,:,k);
        elseif ismatrix(arr),               maskImg = arr; end
    end
    % (3) 파일명 (pivData.imMaskFilename1 : cell/string/char)
    if isempty(maskImg) && isfield(pivData,'imMaskFilename1') && ~isempty(pivData.imMaskFilename1)
        cand = pickPathByIndex(pivData.imMaskFilename1, k);
        if ~isempty(cand) && exist(cand,'file'), maskImg = imread(cand); end
    end
    if isempty(maskImg), maskBin = []; return; end
    if size(maskImg,3) > 1, maskBin = maskImg(:,:,1) > 0;
    else,                   maskBin = maskImg > 0; end
end

function bg = resolveBgFrame(pivData, k, fileList, folderList)
% 프레임 k의 배경 원본 이미지를 반환. 없으면 [] 반환.
    bg = [];
    % (1) 배열 (pivData.imArray1)
    if isempty(bg) && isfield(pivData,'imArray1') && ~isempty(pivData.imArray1)
        arr = pivData.imArray1;
        if ndims(arr)==3 && size(arr,3)>=k, bg = arr(:,:,k);
        elseif ismatrix(arr),               bg = arr; end
    end
    % (2) pivData.imFilename1 (cell/string/char)
    if isempty(bg) && isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
        cand = pickPathByIndex(pivData.imFilename1, k);
        if ~isempty(cand) && exist(cand,'file'), bg = imread(cand); end
    end
    % (3) base workspace fileList
    if isempty(bg) && ~isempty(fileList)
        idx = min(k, numel(fileList));
        f = char(string(fileList{idx}));
        if exist(f,'file'), bg = imread(f); end
    end
    % (4) 폴더 스캔 목록
    if isempty(bg) && ~isempty(folderList)
        idx = min(k, numel(folderList));
        if exist(folderList{idx},'file'), bg = imread(folderList{idx}); end
    end
end

function p = pickPathByIndex(raw, k)
% cell/string/char 경로 컨테이너에서 k번째 경로(char)를 안전하게 추출.
    p = '';
    if iscell(raw)
        idx = min(k, numel(raw));
        v = raw{idx};
        if ischar(v),                       p = v;
        elseif isstring(v) && isscalar(v),  p = char(v); end
    elseif isstring(raw)
        if isscalar(raw), p = char(raw);
        else,             p = char(raw(min(k,numel(raw)))); end
    elseif ischar(raw)
        p = raw;
    end
end

function list = scanImages(folder)
% 폴더 내 이미지(.png 우선 → .bmp → .tif → .jpg)를 이름순 정렬하여 반환.
    exts = {'*.png','*.bmp','*.tif','*.tiff','*.jpg','*.jpeg'};
    D = [];
    for e = 1:numel(exts)
        D = dir(fullfile(folder, exts{e}));
        if ~isempty(D), break; end
    end
    if isempty(D), list = {}; return; end
    [~,order] = sort({D.name});
    list = fullfile(folder, {D(order).name});
end
