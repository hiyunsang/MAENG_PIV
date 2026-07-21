function chipMask = MAENG_ChipBoundaryMask(pivData)
% MAENG_ChipBoundaryMask — discontinuous 칩의 "프레임별 칩/void 경계 마스크" 다중단서 검출
% ----------------------------------------------------------------------------
%  목적: 매 프레임 이동하는 칩-비칩 경계(갭/void)를 자동 검출하여
%        MAENG_StrainmapFwd의 frame_wall에 OR로 넣을 수 있는 마스크 chipMask 생성.
%        => void가 wall에 들어가면 inpaint_nans가 갭을 가로질러 메우지 않고,
%           nan_grad가 같은 쪽 재료만으로 편측차분 => 경계 가짜 변형률 제거.
%
%  다중 단서 융합 (진짜 전단대는 네 단서 모두에서 안전 → 과잉 마스킹 없음):
%    (1) 영상   : 어둡고(저강도) AND 평탄(저텍스처) 노드 = void  [Otsu 자동임계]
%    (2) 품질   : ccPeak 낮음 = decorrelation 경계        [필드 있으면]
%    (3) 발산   : |∇·v| 큼 = 분리/void (소성 평면유동 비압축이라 전단대는 ≈0)
%    (4) 중앙값 : 정규화 중앙값 잔차 큼 = 고립 outlier 벡터 (Westerweel–Scarano)
%    (5) 시간   : 배치 후 3프레임 다수결로 마스크 평활 (깜빡임 제거)
%
%  좌표: 픽셀 (영상/PIV 격자 기준)
%  실행: 인자 없이 F5  또는  chipMask = MAENG_ChipBoundaryMask(pivData)
%        F5 → 미리보기(4분할) → "전체 배치?" → chipMask 저장 + frame_wall 통합코드 출력
% ----------------------------------------------------------------------------

  %% ===== 사용자 파라미터 =====
  P.WIN         = [];     % 영상 텍스처 윈도[px], 빈값 = iaStepX
  P.INT_SCALE   = 0.90;   % Otsu 임계 스케일 (<1 = 더 어두운 것만 void로)
  P.STD_PCTL    = 30;     % 텍스처 하위 % = "평탄"(void 후보) 기준
  P.QUAL_THRESH = 0.50;   % ccPeak 이 값 미만 = 불량 (ccPeak 없으면 자동 무시)
  P.DIV_K       = 5;      % 발산 robust-z 임계 (median ± K·MAD)
  P.MED_THRESH  = 2.5;    % 정규화 중앙값 잔차 임계 (보통 2~3)
  P.MIN_AREA    = 3;      % 최소 덩어리 크기[노드] (이하 제거)
  P.CLOSE_RAD   = 1;      % 형태학 닫힘 반경[노드]
  P.DILATE_BAND = 1;      % 경계 안전 밴드 확장[노드] (창 오염 여유)
  TEMPORAL_SMOOTH = true; % 배치 후 3프레임 다수결 시간 평활

  %% ===== pivData 로드 =====
  if nargin<1 || isempty(pivData)
    if evalin('base','exist(''pivData'',''var'')'), pivData = evalin('base','pivData');
    else
      [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0), chipMask=[]; return; end
      S=load(fullfile(p,f)); fn=fieldnames(S); pivData=S.(fn{1});
    end
  end
  Nt = size(pivData.U,3);
  X  = double(pivData.X); Y = double(pivData.Y); [ny,nx]=size(X);
  dx = double(pivData.iaStepX); dy = double(pivData.iaStepY);
  if isempty(P.WIN), P.WIN = max(5, round(dx)); end

  staticWall = static_wall(pivData,ny,nx);   % 정적 coarse 마스크(bit1) — 출력에선 제외
  fileList   = build_file_list(pivData);

  %% ===== 미리보기 프레임 선택 =====
  a = inputdlg('미리볼 프레임 번호','프레임',1,{num2str(round(Nt/2))});
  if isempty(a), chipMask=[]; return; end
  k = max(1,min(Nt,round(str2double(a{1}))));
  img = get_bg(fileList,pivData,k);
  if isempty(img), error('프레임 %d 영상을 찾지 못했습니다. (1)영상단서가 비활성).',k); end
  cc  = get_ccpeak(pivData,k);
  [bad,dbg] = boundary_mask_one(pivData.U(:,:,k),pivData.V(:,:,k),img,X,Y,dx,dy,cc,staticWall,P);

  %% ===== 미리보기 (4분할) =====
  figure('Name',sprintf('Chip 경계 검출 미리보기 — Frame %d',k),'Color','w', ...
         'Position',[60 60 1180 760]);
  tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

  nexttile;  % (1) 영상 + 검출 경계
  show_img(img); hold on;
  plot(X(staticWall), Y(staticWall), '.', 'Color',[.6 .6 .6], 'MarkerSize',4);
  plot(X(bad), Y(bad), '.', 'Color',[1 0 0], 'MarkerSize',7);
  title('영상 + 검출 경계(빨강) / 정적벽(회색)','FontSize',12);

  nexttile;  % (2) 영상 강도 단서
  imagesc(dbg.nodeI); axis image; colormap(gca,gray); colorbar;
  title('노드 강도 (영상 단서)','FontSize',12);

  nexttile;  % (3) 발산
  imagesc(dbg.divV); axis image; colorbar;
  lim = max(eps, prctile(abs(dbg.divV(~isnan(dbg.divV))),99));
  set(gca,'CLim',[-lim lim]); colormap(gca,parula);
  title('\nabla\cdot v  (분리/void 단서)','FontSize',12);

  nexttile;  % (4) 단서 기여 합성
  comp = double(dbg.imgVoid) + 2*double(dbg.qualBad) + 4*double(dbg.divBad) + 8*double(dbg.medBad);
  imagesc(comp); axis image; colorbar; colormap(gca,turbo);
  title('단서 기여 (영상1 / 품질2 / 발산4 / 중앙값8)','FontSize',12);

  drawnow;

  %% ===== 전체 배치 =====
  q = questdlg('전체 프레임을 배치 처리하여 chipMask를 생성할까요?','배치 처리', ...
               '예','아니오(이 프레임만)','예');
  if strcmp(q,'예')
    chipMask = false(ny,nx,Nt);
    hw = waitbar(0,'경계 마스크 계산 중...');
    for kk = 1:Nt
      im = get_bg(fileList,pivData,kk);
      c  = get_ccpeak(pivData,kk);
      chipMask(:,:,kk) = boundary_mask_one(pivData.U(:,:,kk),pivData.V(:,:,kk), ...
                                           im,X,Y,dx,dy,c,staticWall,P);
      if mod(kk,5)==0 || kk==Nt, waitbar(kk/Nt,hw,sprintf('경계 마스크 %d/%d',kk,Nt)); end
    end
    close(hw);
    if TEMPORAL_SMOOTH, chipMask = temporal_majority(chipMask); end   % (5) 시간 평활

    assignin('base','chipMask',chipMask);
    try, save('chipMask.mat','chipMask','-v7.3'); catch, end
    fprintf(['\n>> chipMask 생성 완료: %d×%d×%d.  base 작업공간 + chipMask.mat 저장.\n', ...
             '------------------------------------------------------------------\n', ...
             ' MAENG_StrainmapFwd 의 frame_wall 함수에 아래 블록을 추가하세요\n', ...
             ' ("try, wm = wm | (bitget...)" 줄 다음, 함수 end 직전):\n\n', ...
             '   if evalin(''base'',''exist(''''chipMask'''',''''var'''')'')\n', ...
             '     cm = evalin(''base'',''chipMask'');\n', ...
             '     wm = wm | cm(:,:,min(k,size(cm,3)));\n', ...
             '   end\n', ...
             '------------------------------------------------------------------\n'], ...
             ny,nx,Nt);
  else
    chipMask = bad;   % 단일 프레임 마스크 반환
  end
end

%% ============================================================
%% 핵심: 단일 프레임 경계 마스크 (4단서 융합)
%% ============================================================
function [bad,dbg] = boundary_mask_one(U,V,img,X,Y,dx,dy,ccPeak,staticWall,P)
  U = double(U); V = double(V);          % single → double (inpaint_nans sparse * 호환)
  [ny,nx] = size(U);

  % --- (1) 영상 단서: 어둡고 AND 평탄 = void ---
  imgVoid = false(ny,nx);
  if ~isempty(img)
    [nodeI,nodeS] = node_stats(img, X, Y, P.WIN);
    lo = prctile(nodeI(:),1); hi = prctile(nodeI(:),99);
    Inorm = min(max((nodeI - lo)/(hi-lo+eps),0),1);          % [0,1] 정규화(NaN 유지)
    try, lvl = graythresh(Inorm(~isnan(Inorm))); catch, lvl = 0.5; end
    Sn = nodeS / max(nodeS(:)+eps);
    sThresh = prctile(Sn(~isnan(Sn)), P.STD_PCTL);
    imgVoid = (Inorm < lvl*P.INT_SCALE) & (Sn < sThresh);
    imgVoid(isnan(Inorm)) = false;
  else
    nodeI = nan(ny,nx);
  end

  % --- (2) 품질 단서: ccPeak 낮음 ---
  qualBad = false(ny,nx);
  if ~isempty(ccPeak) && isequal(size(ccPeak),[ny nx])
    qualBad = ccPeak < P.QUAL_THRESH;
  end

  % --- (3) 발산 단서: |∇·v| 큼 (전단대는 ≈0이라 안전) ---
  Uf = inpaint_nans(U,4); Vf = inpaint_nans(V,4);
  [dUx,~] = nan_grad(Uf,dx,dy);
  [~,dVy] = nan_grad(Vf,dx,dy);
  divV = dUx + dVy;
  md = median(divV(:),'omitnan');
  ma = 1.4826*median(abs(divV(:)-md),'omitnan') + eps;       % robust σ
  divBad = abs(divV - md) > P.DIV_K*ma;

  % --- (4) 중앙값 검정: 고립 outlier 벡터 ---
  rU = norm_median_resid(Uf); rV = norm_median_resid(Vf);
  medBad = max(rU,rV) > P.MED_THRESH;

  % --- 융합 ---
  bad = imgVoid | qualBad | divBad | medBad;
  bad(staticWall) = false;                                   % 정적벽은 frame_wall에서 별도 OR

  % --- 형태학 정리 ---
  bad = bwareaopen(bad, P.MIN_AREA);                         % 자잘한 덩어리 제거
  bad = imclose(bad, strel('disk', P.CLOSE_RAD));            % 끊긴 경계 잇기
  if P.DILATE_BAND>0, bad = imdilate(bad, strel('disk',P.DILATE_BAND)); end

  dbg.imgVoid=imgVoid; dbg.qualBad=qualBad; dbg.divBad=divBad; dbg.medBad=medBad;
  dbg.divV=divV; dbg.nodeI=nodeI;
end

%% ============================================================
%% 로컬: 노드별 국소 평균강도 + 국소 표준편차(텍스처)
%% ============================================================
function [nodeI,nodeS] = node_stats(img, X, Y, w)
  img = double(img);
  if size(img,3)==3, img = double(rgb2gray(uint8(img))); end
  ksz = max(3, 2*round(w/2)+1);                              % 홀수 윈도
  h  = fspecial('average', ksz);
  mu  = imfilter(img,    h, 'replicate');
  mu2 = imfilter(img.^2, h, 'replicate');
  sd  = sqrt(max(mu2 - mu.^2, 0));
  nodeI = interp2(mu, X, Y, 'linear', NaN);                 % 노드 위치에서 샘플
  nodeS = interp2(sd, X, Y, 'linear', NaN);
end

%% ============================================================
%% 로컬: 정규화 중앙값 잔차 (Westerweel & Scarano 2005)
%% ============================================================
function r = norm_median_resid(F)
  eps0 = 0.10;                                               % px, 노이즈 floor
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

%% ============================================================
%% 로컬: NaN-aware 구배 (벽 경계 편측차분) — MAENG_StrainmapFwd와 동일
%% ============================================================
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

%% ============================================================
%% 로컬: 3프레임 다수결 시간 평활
%% ============================================================
function M = temporal_majority(M)
  [~,~,n]=size(M); if n<3, return; end
  s=double(M);
  acc=s; acc(:,:,2:n-1)=s(:,:,1:n-2)+s(:,:,2:n-1)+s(:,:,3:n);
  out=M;  out(:,:,2:n-1)=acc(:,:,2:n-1)>=2;
  M=out;
end

%% ============================================================
%% 로컬: 정적 벽(coarse 마스크) / ccPeak / 배경 로더
%% ============================================================
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

function show_img(img)
  if isempty(img), return; end
  if size(img,3)==1, img=repmat(img,1,1,3); end
  image([1 size(img,2)],[1 size(img,1)],img); axis image ij;
end