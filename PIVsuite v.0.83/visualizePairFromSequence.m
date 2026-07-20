%% Pair / Mean Velocity Visualizer (Turbo Colormap + Background Image Edition)
% -------------------------------------------------------------------------
% [핵심 기능]
%   - 마스크 영역(공구/자유면)에 원본 이미지를 grayscale 로 채워 표시
%   - 유효 영역(공작물/칩)에는 컬러 속도장을 표시 (turbo 컬러맵)
%   - PIV 그리드 계단 형태 없이 픽셀 단위로 매끄러운 속도장
%   - 마스크 경계 픽셀 단위 정확도 보존
%
% [입력 모드]  (프레임 입력 다이얼로그)
%   - 1 ~ Nt 숫자 입력  -> 해당 단일 pair 속도장
%   - 'a-b' 형식 입력   -> a ~ b 프레임 구간 시간평균 (예: 1-30)
%   - 0 입력 / 빈칸 / 취소 -> 전체 시퀀스 시간평균(Mean) 속도장
%       * 평균 속도장 = U,V 성분을 프레임 축(3차원)으로 시간평균한 표준 평균유동장
%       * 배경/마스크는 단일 프레임이 없으므로 대표 프레임(avgRefFrame) 1장을 사용
%
% [turbo 컬러맵 특징]
%   - jet 의 무지개 형태(파랑→빨강) 유지
%   - 형광 청록/녹색 구간이 자연스러운 색으로 부드럽게 전이
%   - 학술지 권장 (Nature, Science 계열)
% -------------------------------------------------------------------------

%% ===== 사용자 입력부 (여기만 수정) =====
fps        = 1000;      % 촬영 frame rate [frame/sec]
pixelSize  = 0.00500;    % 광학계 보정값 [mm/px]
colorMax   = 1;        % 컬러바 상한 [m/min]
colorMin   = 0;          % 컬러바 하한 [m/min]
bgBrightness = 1.1;      % 배경 이미지 밝기 보정 (1.0 = 원본)
bgContrast   = 1.2;      % 배경 이미지 대비 (1.0 = 원본)
showBoundary = true;     % true: 마스크 경계선 표시
saveFigure = true;       % true: PNG/PDF 저장
maskPathManual = '';     % 마스크 경로 수동 지정 (자동 검출 실패 시)
imgPathManual  = '';     % 원본 이미지 경로 수동 지정 (자동 검출 실패 시)
avgRefFrame    = 0;      % [평균/구간평균 전용] 배경/마스크로 쓸 대표 프레임 번호
                         %   0 = 자동(구간 중앙 프레임), 또는 1 ~ Nt 직접 지정
% =========================================

%% 1. pivData 유효성 검사
if ~exist('pivData','var') || ~isfield(pivData,'U') || size(pivData.U,3) < 2
    error('워크스페이스에 시퀀스 PIV 결과 ''pivData''가 없습니다.');
end
Nt = size(pivData.U, 3);

%% 2. 프레임 번호 입력 다이얼로그 (+ 평균/구간평균 모드 판정)
% -------------------------------------------------------------------------
%  avgMode  = true  : 시간평균 속도장 (전체 또는 구간)
%  avgMode  = false : frameIdx 단일 pair 속도장
%  avgRange = [lo hi]: 평균 구간 (전체평균이면 [1 Nt])
%  판정 규칙
%    - 취소(빈 cell)            -> 전체 평균 (1 ~ Nt)
%    - 빈칸 입력                -> 전체 평균 (1 ~ Nt)
%    - 0 입력                   -> 전체 평균 (1 ~ Nt)
%    - 'a-b' 형식 (예: 1-30)    -> 구간 평균 (a ~ b, 역순 자동 정렬)
%    - 1 ~ Nt 정수              -> 단일 pair
%    - 그 외(문자/음수/범위초과) -> 오류
% -------------------------------------------------------------------------
prompt = sprintf(['분석할 프레임 쌍 번호 입력 (1 ~ %d)\n' ...
                  '[0 또는 빈칸 = 전체 평균]   [a-b = 구간 평균, 예: 1-30]:'], Nt);
answer = inputdlg(prompt, 'Frame Pair Selection', [1 60], {num2str(round(Nt/2))});

avgMode  = false;
avgRange = [1 Nt];          % 평균 구간 [lo hi] (기본: 전체)

if isempty(answer)
    avgMode = true;                                   % 취소 -> 전체 평균
else
    valStr = strtrim(answer{1});
    % 'a-b' 구간 패턴 우선 검사 (양쪽 모두 음이 아닌 정수일 때만 매칭)
    rngTok = regexp(valStr, '^\s*(\d+)\s*-\s*(\d+)\s*$', 'tokens', 'once');

    if isempty(valStr)
        avgMode = true;                               % 빈칸 -> 전체 평균
    elseif ~isempty(rngTok)
        % ----- 구간 평균 모드 (a-b) -----
        a = round(str2double(rngTok{1}));
        b = round(str2double(rngTok{2}));
        lo = min(a, b);   hi = max(a, b);             % 역순 입력 자동 정렬
        if lo < 1 || hi > Nt
            error('구간 범위 초과: %d-%d (유효 범위 1~%d)', a, b, Nt);
        end
        avgMode  = true;
        avgRange = [lo hi];
    else
        % ----- 단일 정수 / 0 판정 -----
        valNum = str2double(valStr);
        if isnan(valNum)
            error('숫자 또는 구간(a-b)을 입력하세요: ''%s''', valStr);
        elseif valNum == 0
            avgMode = true;                           % 0 -> 전체 평균
        else
            frameIdx = round(valNum);
            if frameIdx < 1 || frameIdx > Nt
                error('잘못된 프레임 번호: %s (유효 범위 1~%d)', valStr, Nt);
            end
        end
    end
end

% 평균/구간평균 모드에서 배경/마스크로 사용할 대표 프레임 결정
if avgMode
    if avgRefFrame >= 1 && avgRefFrame <= Nt
        frameIdx = round(avgRefFrame);                % 사용자 지정 대표 프레임
    else
        frameIdx = round((avgRange(1) + avgRange(2)) / 2);  % 기본: 구간 중앙 프레임
        frameIdx = min(max(frameIdx, 1), Nt);
    end
    nAvg = avgRange(2) - avgRange(1) + 1;
    if avgRange(1) == 1 && avgRange(2) == Nt
        fprintf('\n>>> 전체 평균 속도장 분석 시작 (프레임 1~%d, %d장 시간평균)\n', Nt, nAvg);
    else
        fprintf('\n>>> 구간 평균 속도장 분석 시작 (프레임 %d~%d, %d장 시간평균)\n', ...
                avgRange(1), avgRange(2), nAvg);
    end
    fprintf('    배경/마스크 대표 프레임: #%d\n', frameIdx);
else
    fprintf('\n>>> Pair #%d (image %d → %d) 분석 시작\n', frameIdx, frameIdx, frameIdx+1);
end

%% 3. 마스크 이미지 로드
maskImg = [];   maskSrc = '';
if ~isempty(maskPathManual) && exist(maskPathManual,'file')
    maskImg = imread(maskPathManual);   maskSrc = ['수동: ' maskPathManual];
elseif isfield(pivData,'imMaskArray1') && ~isempty(pivData.imMaskArray1)
    maskImg = pivData.imMaskArray1;     maskSrc = 'pivData.imMaskArray1';
elseif isfield(pivData,'imMaskFilename1') && ~isempty(pivData.imMaskFilename1)
    rawPath = pivData.imMaskFilename1;
    candidate = '';
    if iscell(rawPath)
        idx = min(frameIdx, length(rawPath));
        if ischar(rawPath{idx}) || (isstring(rawPath{idx}) && isscalar(rawPath{idx}))
            candidate = char(rawPath{idx});
        end
    elseif isstring(rawPath)
        if isscalar(rawPath), candidate = char(rawPath);
        else, candidate = char(rawPath(min(frameIdx,length(rawPath)))); end
    elseif ischar(rawPath), candidate = rawPath; end
    if ~isempty(candidate) && exist(candidate,'file')
        maskImg = imread(candidate);    maskSrc = candidate;
    end
end
if isempty(maskImg)
    error('마스크 이미지를 찾을 수 없습니다. ''maskPathManual'' 변수를 설정하세요.');
end
fprintf('  마스크: %s\n', maskSrc);

if size(maskImg,3) > 1, maskBin = maskImg(:,:,1) > 0;
else, maskBin = maskImg > 0; end
imH = size(maskBin,1);   imW = size(maskBin,2);

%% 4. 원본 이미지 로드
bgImg = [];   bgSrc = '';
if ~isempty(imgPathManual) && exist(imgPathManual,'file')
    bgImg = imread(imgPathManual);   bgSrc = ['수동: ' imgPathManual];
elseif isfield(pivData,'imArray1') && ~isempty(pivData.imArray1)
    arr = pivData.imArray1;
    if ndims(arr) == 3 && size(arr,3) >= frameIdx
        bgImg = arr(:,:,frameIdx);
    elseif ndims(arr) == 2
        bgImg = arr;
    end
    bgSrc = 'pivData.imArray1';
elseif isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
    rawPath = pivData.imFilename1;
    candidate = '';
    if iscell(rawPath)
        idx = min(frameIdx, length(rawPath));
        if ischar(rawPath{idx}) || (isstring(rawPath{idx}) && isscalar(rawPath{idx}))
            candidate = char(rawPath{idx});
        end
    elseif isstring(rawPath)
        if isscalar(rawPath), candidate = char(rawPath);
        else, candidate = char(rawPath(min(frameIdx,length(rawPath)))); end
    elseif ischar(rawPath), candidate = rawPath; end
    if ~isempty(candidate) && exist(candidate,'file')
        bgImg = imread(candidate);   bgSrc = candidate;
    end
end

if isempty(bgImg)
    warning('원본 이미지를 찾을 수 없습니다. 마스크 영역은 회색으로 표시됩니다.');
    bgImg = uint8(zeros(imH, imW) + 200);
else
    fprintf('  원본 이미지: %s\n', bgSrc);
end

if size(bgImg,3) > 1, bgImg = rgb2gray(bgImg); end
bgImg = double(bgImg);
if size(bgImg,1) ~= imH || size(bgImg,2) ~= imW
    bgImg = imresize(bgImg, [imH imW]);
end
bgImg = bgImg / max(bgImg(:));
bgImg = (bgImg - 0.5) * bgContrast + 0.5;
bgImg = bgImg * bgBrightness;
bgImg = max(0, min(1, bgImg));

%% 5. 속도장 추출 (단일 pair / 시간평균·구간평균 분기)
% -------------------------------------------------------------------------
%  - 단일 pair : readTimeSlice 로 frameIdx 슬라이스 추출 (U/V 는 double 반환)
%  - 시간평균  : U,V 성분을 3차원(프레임 축, avgRange 구간)으로 omitnan 평균
%                 X,Y 는 전 프레임 공통 2D 그리드(pivData.X, pivData.Y)
%                 single -> double 캐스팅으로 inpaint_nans 문제 예방
% -------------------------------------------------------------------------
if avgMode
    X = double(pivData.X);
    Y = double(pivData.Y);
    U = mean(double(pivData.U(:,:,avgRange(1):avgRange(2))), 3, 'omitnan');
    V = mean(double(pivData.V(:,:,avgRange(1):avgRange(2))), 3, 'omitnan');
else
    pairData = pivManipulateData('readTimeSlice', pivData, frameIdx);
    X = double(pairData.X);   Y = double(pairData.Y);
    U = double(pairData.U);   V = double(pairData.V);
end

%% 6. 단위 변환
convFactor = pixelSize * fps * 0.06;
U_phys = U * convFactor;
V_phys = V * convFactor;

%% 7. NaN 외삽
if any(isnan(U_phys(:)))
    U_filled = inpaint_nans(U_phys, 2);
    V_filled = inpaint_nans(V_phys, 2);
else
    U_filled = U_phys;   V_filled = V_phys;
end

%% 8. 픽셀 해상도 업샘플링
xGrid = X(1,:);   yGrid = Y(:,1);
[Xpix, Ypix] = meshgrid(1:imW, 1:imH);

F_U = griddedInterpolant({yGrid, xGrid}, U_filled, 'cubic', 'linear');
F_V = griddedInterpolant({yGrid, xGrid}, V_filled, 'cubic', 'linear');
U_pix = F_U(Ypix, Xpix);
V_pix = F_V(Ypix, Xpix);

Umag_pix = sqrt(U_pix.^2 + V_pix.^2);

validData = Umag_pix(maskBin);
fprintf('  데이터 범위: %.3f ~ %.3f m/min (colorMax=%.2f)\n', ...
        min(validData), max(validData), colorMax);

%% 9. Turbo 컬러맵 정의 (구버전 호환)
% -------------------------------------------------------------------------
% MATLAB R2020b 이상에서는 turbo() 함수가 기본 제공됩니다.
% 그 미만 버전에서는 7-stop 보간으로 turbo 를 수동 정의합니다.
% (Google AI Blog "Turbo, An Improved Rainbow Colormap" 기반)
% -------------------------------------------------------------------------
nColors = 256;
try
    cmap = turbo(nColors);          % R2020b+ 내장
catch
    % Turbo key-color stops (8개) — 공식 turbo 컬러맵 근사
    keyC = [ 0.18995, 0.07176, 0.23217;    % deep purple
             0.27149, 0.41614, 0.81616;    % blue
             0.13990, 0.71880, 0.84314;    % cyan-blue
             0.16444, 0.89409, 0.55834;    % green-cyan (자연스러운)
             0.71776, 0.95977, 0.20755;    % yellow-green
             0.97819, 0.79410, 0.20194;    % yellow-orange
             0.95201, 0.36915, 0.10882;    % orange-red
             0.47960, 0.01583, 0.01055];   % dark red
    ts = linspace(0, 1, size(keyC,1)).';
    tq = linspace(0, 1, nColors).';
    cmap = [interp1(ts, keyC(:,1), tq, 'pchip'), ...
            interp1(ts, keyC(:,2), tq, 'pchip'), ...
            interp1(ts, keyC(:,3), tq, 'pchip')];
    cmap = max(0, min(1, cmap));
end

%% 10. RGB 합성 이미지 생성
UmagNorm = (Umag_pix - colorMin) / (colorMax - colorMin);
UmagNorm = max(0, min(1, UmagNorm));
colorIdx = round(UmagNorm * (nColors-1)) + 1;
colorIdx = max(1, min(nColors, colorIdx));

velR = reshape(cmap(colorIdx(:), 1), imH, imW);
velG = reshape(cmap(colorIdx(:), 2), imH, imW);
velB = reshape(cmap(colorIdx(:), 3), imH, imW);

rgbImg = zeros(imH, imW, 3);
rgbImg(:,:,1) = velR .* maskBin + bgImg .* (~maskBin);
rgbImg(:,:,2) = velG .* maskBin + bgImg .* (~maskBin);
rgbImg(:,:,3) = velB .* maskBin + bgImg .* (~maskBin);
rgbImg = max(0, min(1, rgbImg));

%% 11. Figure 생성
hFig = figure(100); clf;
set(hFig, 'Color','w', 'Units','centimeters', 'Position',[3 3 16 14]);

tl = tiledlayout(hFig, 1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
ax = nexttile(tl);

%% 12. RGB 이미지 표시
image(ax, [1 imW], [1 imH], rgbImg);

colormap(ax, cmap);
try
    clim(ax, [colorMin, colorMax]);
catch
    caxis(ax, [colorMin, colorMax]); %#ok<CAXIS>
end

%% 13. 마스크 경계선
if showBoundary
    hold(ax, 'on');
    B = bwboundaries(maskBin, 8, 'noholes');
    for k = 1:length(B)
        boundary = B{k};
        plot(ax, boundary(:,2), boundary(:,1), 'k-', 'LineWidth', 1.5);
    end
    hold(ax, 'off');
end

%% 14. 축 외관 + 제목 (모드별 분기)
axis(ax, 'image');
axis(ax, [1 imW 1 imH]);
set(ax, 'YDir','reverse', ...
        'FontName','Arial', 'FontSize',11, ...
        'LineWidth',1.2, 'TickDir','out', 'Box','on', 'Layer','top');

xlabel(ax, 'x [px]', 'FontSize',12, 'FontName','Arial');
ylabel(ax, 'y [px]', 'FontSize',12, 'FontName','Arial');

if avgMode
    nAvg = avgRange(2) - avgRange(1) + 1;
    if avgRange(1) == 1 && avgRange(2) == Nt
        titleStr = sprintf('Mean Velocity Field — Average of %d pairs', nAvg);
    else
        titleStr = sprintf('Mean Velocity Field — Average of frames %d-%d (%d pairs)', ...
                           avgRange(1), avgRange(2), nAvg);
    end
else
    titleStr = sprintf('Velocity Field — Pair #%d (image %d \\rightarrow %d)', ...
                       frameIdx, frameIdx, frameIdx+1);
end
title(ax, titleStr, ...
      'FontWeight','normal', 'FontSize',12, 'Interpreter','tex', 'FontName','Arial');

%% 15. 컬러바
cb = colorbar(ax, 'Location', 'southoutside');
cb.Label.String = 'Material velocity v_m  [m/min]';
cb.Label.FontSize = 12;
cb.Label.FontName = 'Arial';
cb.FontSize = 10;
cb.FontName = 'Arial';
cb.LineWidth = 1.0;
cb.TickDirection = 'out';
cb.Ticks = linspace(colorMin, colorMax, 5);

range = colorMax - colorMin;
if range >= 10,    fmt = '%.0f';
elseif range >= 1, fmt = '%.2f';
else,              fmt = '%.3f'; end
cb.TickLabels = arrayfun(@(v) sprintf(fmt, v), cb.Ticks, 'UniformOutput', false);

%% 16. 저장 (모드별 파일명 분기)
if saveFigure
    if avgMode
        if avgRange(1) == 1 && avgRange(2) == Nt
            saveName = sprintf('mean_velocity_%03dpairs', avgRange(2)-avgRange(1)+1);
        else
            saveName = sprintf('mean_velocity_f%03d-%03d', avgRange(1), avgRange(2));
        end
    else
        saveName = sprintf('pair_%03d_velocity', frameIdx);
    end
    exportgraphics(hFig, [saveName,'.png'], 'Resolution', 600);
    exportgraphics(hFig, [saveName,'.pdf'], 'ContentType', 'vector');
    fprintf('  [저장] %s.png / %s.pdf\n', saveName, saveName);
end

%% 17. 콘솔 요약 (모드별 헤더 분기)
if avgMode
    nAvg = avgRange(2) - avgRange(1) + 1;
    if avgRange(1) == 1 && avgRange(2) == Nt
        fprintf('\n=== 평균 속도장 요약 (전체 %d pairs) ===\n', nAvg);
    else
        fprintf('\n=== 구간 평균 속도장 요약 (프레임 %d~%d, %d pairs) ===\n', ...
                avgRange(1), avgRange(2), nAvg);
    end
else
    fprintf('\n=== Pair #%d 속도 요약 ===\n', frameIdx);
end
fprintf('  |V| 최댓값 : %.3f m/min\n', max(validData));
fprintf('  |V| 평균   : %.3f m/min\n', mean(validData));
fprintf('  |V| 중앙값 : %.3f m/min\n', median(validData));
fprintf('==============================\n\n');