function MAENG_ChipMaskPlayback(pivData)
% MAENG_ChipMaskPlayback — 칩/void 경계 마스크를 영상 위에 쭈루룩 재생 (판단용)
% ----------------------------------------------------------------------------
%  표시할 각 프레임의 경계 마스크를 "라이브로" 계산해서 원본 영상 위에
%  빨간 외곽선 + 반투명 채움으로 오버레이하여 애니메이션.
%  => 상단 P 파라미터를 바꾸고 F5만 다시 누르면 즉시 반영 (배치 재생성 불필요).
%     판단 → 튜닝 → 재확인 루프를 빠르게. 마음에 들면 같은 P를
%     MAENG_ChipBoundaryMask 에 넣고 전체 배치로 chipMask 생성.
%
%  검출 로직은 MAENG_ChipBoundaryMask 와 동일(영상+품질+발산+중앙값 융합).
%  실행: 인자 없이 F5  또는  MAENG_ChipMaskPlayback(pivData)
% ----------------------------------------------------------------------------

  %% ===== 검출 파라미터 (MAENG_ChipBoundaryMask 와 동일하게 유지) =====
  P.WIN         = [];     % 영상 텍스처 윈도[px], 빈값=iaStepX
  P.INT_SCALE   = 0.90;   % Otsu 임계 스케일 (<1=더 어두운 것만 void)
  P.STD_PCTL    = 30;     % 텍스처 하위 % = "평탄"(void 후보)
  P.QUAL_THRESH = 0.50;   % ccPeak 이하 = 불량 (없으면 무시)
  P.DIV_K       = 5;      % 발산 robust-z 임계
  P.MED_THRESH  = 2.5;    % 정규화 중앙값 잔차 임계
  P.MIN_AREA    = 1;      % 최소 덩어리[노드]
  P.CLOSE_RAD   = 1;      % 닫힘 반경[노드]
  P.DILATE_BAND = 1;      % 경계 밴드 확장[노드]

  %% ===== 재생/표시 파라미터 =====
  ASK_FRAMES   = true;
  t_start      = 1;  t_end = [];      % 빈값=끝까지 (라이브라 범위를 줄여서 보는 걸 권장)
  PAUSE        = 0.03;
  FILL_ALPHA   = 0.33;                % 채움 투명도
  SHOW_OUTLINE = true;                % 경계 외곽선
  OUTLINE_LW   = 1.6;
  SHOW_FILL    = true;                % 반투명 채움
  DO_MP4       = false;
  MP4_FPS      = 20;

  %% ===== pivData 로드 =====
  if nargin<1 || isempty(pivData)
    if evalin('base','exist(''pivData'',''var'')'), pivData = evalin('base','pivData');
    else
      [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0), return; end
      S=load(fullfile(p,f)); fn=fieldnames(S); pivData=S.(fn{1});
    end
  end
  Nt = size(pivData.U,3);
  X  = double(pivData.X); Y = double(pivData.Y); [ny,nx]=size(X);
  dx = double(pivData.iaStepX); dy = double(pivData.iaStepY);
  if isempty(P.WIN), P.WIN = max(5,round(dx)); end
  staticWall = static_wall(pivData,ny,nx);
  fileList   = build_file_list(pivData);

  bg0 = get_bg(fileList,pivData,1);
  if isfield(pivData,'imSizeX'), W=pivData.imSizeX; else, W=size(bg0,2); end
  if isfield(pivData,'imSizeY'), H=pivData.imSizeY; else, H=size(bg0,1); end

  %% ===== 프레임 범위 =====
  if isempty(t_end), t_end=Nt; end
  if ASK_FRAMES
    a=inputdlg({'시작 프레임','끝 프레임 (라이브 계산: 200장 이내 권장)'}, ...
               '재생 범위',1,{num2str(t_start),num2str(min(t_end,t_start+199))});
    if ~isempty(a), t_start=str2double(a{1}); t_end=str2double(a{2}); end
  end
  t_start=max(1,min(Nt,round(t_start)));
  t_end  =max(t_start,min(Nt,round(t_end)));

  %% ===== MP4 =====
  if DO_MP4
    [vf,vp]=uiputfile('*.mp4','MP4 저장 위치');
    if isequal(vf,0), DO_MP4=false;
    else, vw=VideoWriter(fullfile(vp,vf),'MPEG-4'); vw.FrameRate=MP4_FPS; vw.Quality=100; open(vw); end
  end

  %% ===== 오버레이용 빨강 레이어 (격자 해상도, image가 영상크기로 stretch) =====
  redC = cat(3, ones(ny,nx), zeros(ny,nx), zeros(ny,nx));
  validN = nnz(~staticWall);

  %% ===== 재생 루프 =====
  hFig=figure('Name','Chip 경계 마스크 재생 (판단용)','Color','w','Position',[80 80 1000 660]);
  vidSize=[];
  for k=t_start:t_end
    img = get_bg(fileList,pivData,k);
    m   = boundary_mask_one(pivData.U(:,:,k),pivData.V(:,:,k),img,X,Y,dx,dy, ...
                            get_ccpeak(pivData,k), staticWall, P);

    clf(hFig); ax=axes('Parent',hFig);
    if ~isempty(img)
      if size(img,3)==1, img=repmat(img,1,1,3); end
      image(ax,[1 W],[1 H],img);
    end
    axis(ax,'image','ij'); hold(ax,'on');

    if SHOW_FILL
      hov=image(ax,[1 W],[1 H],redC); set(hov,'AlphaData',FILL_ALPHA*double(m));
    end
    if SHOW_OUTLINE
      B=bwboundaries(m);
      for b=1:numel(B)
        rc=B{b};
        xb=X(sub2ind(size(X),rc(:,1),rc(:,2)));
        yb=Y(sub2ind(size(Y),rc(:,1),rc(:,2)));
        plot(ax,xb,yb,'r-','LineWidth',OUTLINE_LW);
      end
    end

    frac=100*nnz(m)/max(1,validN);
    title(ax,sprintf('Frame %d / %d   —   마스크 노드 %.1f%% (유효노드 대비)', ...
          k,t_end,frac),'FontSize',13);
    axis(ax,[1 W 1 H]); drawnow;

    if DO_MP4
      fr=print(hFig,'-RGBImage','-r120');
      if isempty(vidSize), vidSize=[size(fr,1) size(fr,2)]; end
      if size(fr,1)~=vidSize(1)||size(fr,2)~=vidSize(2), fr=imresize(fr,vidSize); end
      writeVideo(vw,fr);
    end
    pause(PAUSE);
  end
  if DO_MP4, close(vw); fprintf('MP4 저장 완료\n'); end
  disp('>> 경계 마스크 재생 완료.  파라미터가 맘에 들면 같은 P 값을 MAENG_ChipBoundaryMask 에 넣고 배치하세요.');
end

%% ============================================================
%% 핵심: 단일 프레임 경계 마스크 (MAENG_ChipBoundaryMask 와 동일)
%% ============================================================
function bad = boundary_mask_one(U,V,img,X,Y,dx,dy,ccPeak,staticWall,P)
  U = double(U); V = double(V);
  [ny,nx] = size(U);

  % (1) 영상: 어둡고 AND 평탄 = void
  imgVoid = false(ny,nx);
  if ~isempty(img)
    [nodeI,nodeS] = node_stats(img, X, Y, P.WIN);
    lo = prctile(nodeI(:),1); hi = prctile(nodeI(:),99);
    Inorm = min(max((nodeI - lo)/(hi-lo+eps),0),1);
    try, lvl = graythresh(Inorm(~isnan(Inorm))); catch, lvl = 0.5; end
    Sn = nodeS / max(nodeS(:)+eps);
    sThresh = prctile(Sn(~isnan(Sn)), P.STD_PCTL);
    imgVoid = (Inorm < lvl*P.INT_SCALE) & (Sn < sThresh);
    imgVoid(isnan(Inorm)) = false;
  end

  % (2) 품질: ccPeak 낮음
  qualBad = false(ny,nx);
  if ~isempty(ccPeak) && isequal(size(ccPeak),[ny nx])
    qualBad = ccPeak < P.QUAL_THRESH;
  end

  % (3) 발산: |∇·v| 큼 (전단대는 ≈0)
  Uf = inpaint_nans(U,4); Vf = inpaint_nans(V,4);
  [dUx,~] = nan_grad(Uf,dx,dy);
  [~,dVy] = nan_grad(Vf,dx,dy);
  divV = dUx + dVy;
  md = median(divV(:),'omitnan');
  ma = 1.4826*median(abs(divV(:)-md),'omitnan') + eps;
  divBad = abs(divV - md) > P.DIV_K*ma;

  % (4) 중앙값 검정: 고립 outlier
  rU = norm_median_resid(Uf); rV = norm_median_resid(Vf);
  medBad = max(rU,rV) > P.MED_THRESH;

  % 융합 + 정리
  bad = imgVoid | qualBad | divBad | medBad;
  bad(staticWall) = false;
  bad = bwareaopen(bad, P.MIN_AREA);
  bad = imclose(bad, strel('disk', P.CLOSE_RAD));
  if P.DILATE_BAND>0, bad = imdilate(bad, strel('disk',P.DILATE_BAND)); end
end

%% ============================================================
%% 로컬 (MAENG_ChipBoundaryMask 와 동일)
%% ============================================================
function [nodeI,nodeS] = node_stats(img, X, Y, w)
  img = double(img);
  if size(img,3)==3, img = double(rgb2gray(uint8(img))); end
  ksz = max(3, 2*round(w/2)+1);
  h  = fspecial('average', ksz);
  mu  = imfilter(img,    h, 'replicate');
  mu2 = imfilter(img.^2, h, 'replicate');
  sd  = sqrt(max(mu2 - mu.^2, 0));
  nodeI = interp2(mu, X, Y, 'linear', NaN);
  nodeS = interp2(sd, X, Y, 'linear', NaN);
end

function r = norm_median_resid(F)
  eps0 = 0.10;
  [ny,nx] = size(F);
  pad = nan(ny+2,nx+2); pad(2:end-1,2:end-1) = F;
  nb = nan(ny,nx,8); idx = 1;
  for di=-1:1
    for dj=-1:1
      if di==0 && dj==0, continue; end
      nb(:,:,idx) = pad(2+di:end-1+di, 2+dj:end-1+dj); idx = idx+1;
    end
  end
  med    = median(nb,3,'omitnan');
  res    = abs(F - med);
  medres = median(abs(nb - med),3,'omitnan');
  r = res ./ (medres + eps0);
  r(isnan(r)) = 0;
end

function [dFdx,dFdy] = nan_grad(F,dx,dy)
  [ny,nx]=size(F);
  dFdx=nan(ny,nx); dFdy=nan(ny,nx);
  vF=~isnan(F);
  L=[nan(ny,1), F(:,1:end-1)];  R=[F(:,2:end), nan(ny,1)];
  vL=~isnan(L); vR=~isnan(R);
  c=vF&vL&vR; dFdx(c)=(R(c)-L(c))/(2*dx);
  f=vF&~vL&vR; dFdx(f)=(R(f)-F(f))/dx;
  b=vF&vL&~vR; dFdx(b)=(F(b)-L(b))/dx;
  Uu=[nan(1,nx); F(1:end-1,:)];  Dd=[F(2:end,:); nan(1,nx)];
  vU=~isnan(Uu); vD=~isnan(Dd);
  c=vF&vU&vD; dFdy(c)=(Dd(c)-Uu(c))/(2*dy);
  f=vF&~vU&vD; dFdy(f)=(Dd(f)-F(f))/dy;
  b=vF&vU&~vD; dFdy(b)=(F(b)-Uu(b))/dy;
end

function w = static_wall(pivData,ny,nx)
  w=false(ny,nx);
  if isfield(pivData,'Status') && ~isempty(pivData.Status)
    St=pivData.Status; if ndims(St)>=3, St=St(:,:,1); end
    try, w = bitget(uint16(St),1)>0; catch, end
  end
end

function c = get_ccpeak(pivData,k)
  c=[];
  if isfield(pivData,'ccPeak') && ~isempty(pivData.ccPeak)
    C=pivData.ccPeak; if ndims(C)>=3, c=C(:,:,min(k,size(C,3))); else, c=C; end
  end
end

function fileList = build_file_list(pivData)
  fileList={};
  try
    if evalin('base','exist(''fileList'',''var'')')
      fileList=evalin('base','fileList'); if ~isempty(fileList), return; end
    end
  catch, end
  for fld={'imFilename1','imFilename2'}
    f=fld{1};
    if isfield(pivData,f)&&iscell(pivData.(f))&&~isempty(pivData.(f)), fileList=pivData.(f); return; end
  end
  if isfield(pivData,'imagePath')&&exist(pivData.imagePath,'dir')
    D=dir(fullfile(pivData.imagePath,'*.png'));
    if isempty(D),D=dir(fullfile(pivData.imagePath,'*.bmp'));end
    if isempty(D),D=dir(fullfile(pivData.imagePath,'*.tif'));end
    if ~isempty(D),[~,ix]=sort({D.name}); fileList=fullfile(pivData.imagePath,{D(ix).name}); end
  end
end

function bg = get_bg(fileList,pivData,idx)
  bg=[];
  if ~isempty(fileList), j=min(idx,numel(fileList)); try, bg=imread(fileList{j}); catch, end; end
  if isempty(bg)
    for fld={'imFilename1','imFilename2'}
      f=fld{1};
      if isfield(pivData,f)
        fn=pivData.(f); if iscell(fn), fn=fn{min(idx,numel(fn))}; end
        if (ischar(fn)||isstring(fn))&&exist(fn,'file'), try, bg=imread(fn); catch, end; end
      end
      if ~isempty(bg), break; end
    end
  end
end
