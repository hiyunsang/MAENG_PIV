%% ===== 배경/마스크 준비 (bg, isMaskedGrid) =====
% 1) 배경 경로 자동 추출(없으면 직접 bgPath 지정)
if ~exist('bg','var')
    if ~exist('bgPath','var')
        if isfield(pivData2,'imFilename2') && ~isempty(pivData2.imFilename2)
            bgPath = pivData2.imFilename2;
        elseif isfield(pivData2,'imFilename1') && ~isempty(pivData2.imFilename1)
            bgPath = pivData2.imFilename1;
        else
            error('배경 이미지 경로가 없습니다. bgPath = ''...'' 로 직접 지정하세요.');
        end
    end
    bg = imread(bgPath);
end

% 2) 마스크가 아직 없으면(옵션) 전부 표시로 초기화
if ~exist('isMaskedGrid','var') || isempty(isMaskedGrid)
    isMaskedGrid = false(size(Vsl));
end

% ===== 안전한 슬라이스 선택 (2D/3D 모두 대응) =====
Vraw = pivData2.V;
Uraw = pivData2.U;

if ndims(Vraw) == 3
    kt = size(Vraw,3);              % 마지막 프레임
    Vsl = Vraw(:,:,kt);
    Usl = Uraw(:,:,kt);
    if isfield(pivData2,'X'), Xg = pivData2.X(:,:,kt); else, Xg = []; end
    if isfield(pivData2,'Y'), Yg = pivData2.Y(:,:,kt); else, Yg = []; end
else
    Vsl = Vraw;
    Usl = Uraw;
    if isfield(pivData2,'X'), Xg = pivData2.X; else, Xg = []; end
    if isfield(pivData2,'Y'), Yg = pivData2.Y; else, Yg = []; end
end

% ===== 이동 기준틀(평균 유입 속도 제거) =====
% 우측 가장자리 몇 열 평균 (열 개수 부족시 자동 보정)
nx = size(Vsl,2);
cols = max(1, nx-5) : max(1, nx-1);

Umean = mean(Usl(:,cols), 'all', 'omitnan');
Vmean = mean(Vsl(:,cols), 'all', 'omitnan');

Usl = Usl - Umean;
Vsl = Vsl - Vmean;

% ===== V 임계값 색상 분류 =====
thr_hi = -1.5;   % high 경계 (빨강)
thr_lo = -3;   % low  경계 (파랑)

M = nan(size(Vsl));
M(Vsl >  thr_hi)                 = 3;  % red   (high)
M(Vsl <= thr_hi & Vsl >= thr_lo) = 2;  % yellow(medium)
M(Vsl <  thr_lo)                 = 1;  % blue  (low)

%% ===== 플롯: 배경 → 컬러오버레이 (원색, 불투명), 축/격자/컬러바 없음 =====
[H,W,~] = size(bg);

f = figure(6); clf; set(f,'Color','w','Units','pixels','Position',[100 100 W H]);
ax = axes('Parent',f,'Units','normalized','Position',[0 0 1 1]);  % 꽉 채우기
imshow(bg,'Parent',ax); hold(ax,'on');
set(ax,'YDir','reverse');  % PIV 좌표와 정합

% 분류 오버레이
hImg = imagesc(ax, Xg(1,:), Yg(:,1), M);
colormap(ax, [1 0 0; 1 1 0; 0 0 1]);   % red / yellow / blue (원색)
set(ax,'CLim',[1 3]);

% 마스크는 투명, 나머지는 불투명(진한 색)
if exist('isMaskedGrid','var')
    alphaMap = ones(size(M)); alphaMap(isnan(M) | isMaskedGrid) = 0;
else
    alphaMap = ~isnan(M);
end
set(hImg,'AlphaData', alphaMap);

% 축/눈금/테두리/타이틀/라벨/컬러바 제거 (완전한 원본 느낌)
axis(ax,'image'); axis(ax,'off'); box(ax,'off');
set(ax,'XColor','none','YColor','none','TickLength',[0 0]);

% (필요하면) 저장 — 배경 픽셀 크기 그대로
exportgraphics(f, 'overlay_clean.png', 'Resolution', 300);   % 파일로 저장

% ===== 플롯 =====
figure(6); clf;
hImg = imagesc(Xg(1,:), Yg(:,1), M);
set(gca,'YDir','reverse'); axis image;

% >>> 진한 빨강-노랑-파랑 컬러맵 <<<
colormap([1 0 0; 1 1 0; 0 0 1]);   % [red; yellow; blue]

cb = colorbar; cb.Ticks = [1 2 3];
cb.TickLabels = {sprintf('V_z \\ge %.2f',thr_hi), ...
                 sprintf('%.2f \\le V_z < %.2f',thr_lo,thr_hi), ...
                 sprintf('V_z < %.2f',thr_lo)};

set(hImg,'AlphaData', ~isnan(M)*1);  % 반투명
title('V_z thresholds: red/yellow/blue (moving frame)');
xlabel('X (px)'); ylabel('Y (px)');
