%% 1) 슬라이스 추출 (2D/3D 대응)
Vraw = pivData2.V; Uraw = pivData2.U;
if ndims(Vraw)==3
    kt = size(Vraw,3);
    Vsl = Vraw(:,:,kt);  Usl = Uraw(:,:,kt);
    if isfield(pivData2,'X'), Xg = pivData2.X(:,:,kt); else, Xg = []; end
    if isfield(pivData2,'Y'), Yg = pivData2.Y(:,:,kt); else, Yg = []; end
else
    Vsl = Vraw; Usl = Uraw;
    if isfield(pivData2,'X'), Xg = pivData2.X; else, Xg = []; end
    if isfield(pivData2,'Y'), Yg = pivData2.Y; else, Yg = []; end
end
[ny,nx] = size(Vsl); if isempty(Xg) || isempty(Yg), [Xg,Yg] = meshgrid(1:nx,1:ny); end

%% 2) 이동 기준틀(유입 평균 제거)
cols = max(1,nx-5):nx;
Usl = Usl - mean(Usl(:,cols),'all','omitnan');
Vsl = Vsl - mean(Vsl(:,cols),'all','omitnan');

%% 3) 임계값 분류 (1=파랑, 2=노랑, 3=빨강)
thr_hi = -0.8; thr_lo = -2.9;
M = nan(size(Vsl));
M(Vsl >  thr_hi)                 = 1;   % 빨강
M(Vsl <= thr_hi & Vsl >= thr_lo) = 2;   % 노랑
M(Vsl <  thr_lo)                 = 3;   % 파랑

%% 4) 플롯 (배경/마스크 없음, 원색/불투명)
figure(6); clf; ax = axes('Position',[0 0 1 1]); hold(ax,'on'); set(ax,'YDir','reverse');
hImg = imagesc(ax, Xg(1,:), Yg(:,1), M);
colormap(ax, [0 0 1; 1 1 0; 1 0 0]);     % 1→파랑, 2→노랑, 3→빨강
set(ax,'CLim',[1 3]); set(hImg,'AlphaData', ~isnan(M));
axis(ax,'image'); axis(ax,'off'); box(ax,'off');
