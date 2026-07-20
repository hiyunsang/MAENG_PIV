function out = pivMaterialMaskCheck(pivData)
% pivMaterialMaskCheck — 재료 vs 배경(외부공기 + 세그먼트 사이 빈 갭) 판별 검증 뷰어
%   갭(void)은 '어둑함(void) + 저상관(코히어런트 재료 없음)' 둘 다 해당.
%   변형 중인 재료(전단대)는 '밝음(재료 있음)'이라 저상관이어도 살려야 함.
%   ⇒ OR 규칙 권장:  재료 = (밝음) OR (상관높음)  →  배경 = (어둡고) AND (상관낮음)
%
%   SIGNAL:
%     'either' : 재료=밝거나 OR 상관높음 → 배경=어둡고 AND 저상관 (권장: 갭만 배경, 변형재료 유지)
%     'both'   : 재료=밝고 AND 상관높음 → 배경=어둡거나 OR 저상관 (공격적: 변형재료도 배경될 수 있음)
%     'image'  : 강도만 (까만색=배경)
%     'ccpeak' : 상관만 (저상관=배경)
%
%   표시(3패널): (좌)영상+재료초록+경계시안  (중)강도 셀맵  (우)ccPeak
%   실행: 인자 없이 F5 또는 out = pivMaterialMaskCheck(pivData)
% ----------------------------------------------------------------------------

  %% ===== 사용자 파라미터 =====
  t_start=[]; t_end=[]; ASK_FRAMES=true;

  SIGNAL     = 'either'; % 'either'(권장) | 'both' | 'image' | 'ccpeak'
  INT_THRESH = [30000];       % 강도 임계. []=자동(multithresh 2단계 상위 → 회색 갭도 '어둠'쪽). 숫자=고정
  CC_THRESH  = [];       % ccPeak 임계. []=자동(graythresh). 숫자=고정

  MIN_BLOB   = 8;       % 작은 재료 섬 제거 [격자셀]
  MIN_GAP    = 30;       % 이보다 작은 배경구멍은 메움(잡음 cc-fail); 큰 갭/외부배경은 배경 유지

  TINT_MAT=true; ANIM_PAUSE=0.08; DO_MP4=false; MP4_FPS=10;

  %% ===== pivData 로드 =====
  if nargin<1 || isempty(pivData)
    if evalin('base','exist(''pivData'',''var'')'), pivData = evalin('base','pivData');
    else
      [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0), out=[]; return; end
      S=load(fullfile(p,f)); fn=fieldnames(S); pivData=S.(fn{1});
    end
  end
  ccField = pick_cc_field(pivData);
  needCC = any(strcmpi(SIGNAL,{'either','both','ccpeak'}));
  if isempty(ccField) && needCC
    warning('ccPeak 필드 없음 → SIGNAL=''image''로 전환'); SIGNAL='image';
  end

  Nt = size(pivData.U,3);
  if isempty(t_start), t_start=1; end
  if isempty(t_end),   t_end=Nt; end
  if ASK_FRAMES
    a=inputdlg({'시작 프레임','끝 프레임'},'프레임 범위',1,{num2str(t_start),num2str(t_end)});
    if ~isempty(a), t_start=str2double(a{1}); t_end=str2double(a{2}); end
  end
  t_start=max(1,min(Nt,round(t_start))); t_end=max(t_start,min(Nt,round(t_end)));

  Xpx=double(pivData.X); Ypx=double(pivData.Y);
  minX=min(Xpx(:)); maxX=max(Xpx(:)); minY=min(Ypx(:)); maxY=max(Ypx(:));
  xv=Xpx(1,:); yv=Ypx(:,1).';
  dx=double(pivData.iaStepX); dy=double(pivData.iaStepY);

  fileList = build_file_list(pivData);
  bg0 = get_bg(fileList,pivData,t_start);
  if isempty(bg0), error('배경 이미지를 찾지 못했습니다.'); end
  if isfield(pivData,'imSizeX'), W=pivData.imSizeX; else, W=size(bg0,2); end
  if isfield(pivData,'imSizeY'), H=pivData.imSizeY; else, H=size(bg0,1); end

  hFig=figure('Name','Material vs Background(외부+갭) Check','Color','w','Position',[40 80 1620 540]);
  vidSize=[];
  if DO_MP4
    [vf,vp]=uiputfile('*.mp4','MP4 저장 위치');
    if isequal(vf,0), DO_MP4=false; else
      vw=VideoWriter(fullfile(vp,vf),'MPEG-4'); vw.FrameRate=MP4_FPS; vw.Quality=100; open(vw);
    end
  end

  %% ===== 프레임 루프 =====
  for k=t_start:t_end
    bg = get_bg(fileList,pivData,k);

    % --- 신호 계산 ---
    ci  = cell_intensity(bg,W,H,Xpx,Ypx,dx,dy);     % 셀 평균 강도 ny×nx
    if ~isempty(ccField), ccP=get_cc(pivData,ccField,k); ccP(isnan(ccP))=0; else, ccP=zeros(size(ci)); end

    intThr = auto_int(ci, INT_THRESH);   % 회색 갭이 '어둠'쪽에 들어가도록 상위 임계
    ccThr  = auto_thr(ccP, CC_THRESH);

    matB = ci  > intThr;     % 밝음 = 재료(재료가 있음)
    matC = ccP > ccThr;      % 상관높음 = 재료(코히어런트)
    switch lower(SIGNAL)
      case 'either', material = matB | matC;   % 배경 = 어둡고 AND 저상관 (갭=void)
      case 'both',   material = matB & matC;   % 배경 = 어둡거나 OR 저상관
      case 'image',  material = matB;
      case 'ccpeak', material = matC;
      otherwise,     material = matB | matC;
    end

    % --- 정리: 작은 재료섬 제거 + 작은 배경구멍 메움 (큰 갭/외부배경은 유지) ---
    material = bwareaopen(material, MIN_BLOB);     % 작은 재료 섬 → 배경
    holes = ~material;
    holes = bwareaopen(holes, MIN_GAP);           % MIN_GAP 미만 배경덩어리 제거 → 재료(잡음구멍 메움)
    material = ~holes;                            % 외부배경 + 큰 갭만 배경으로 남음
    nseg = numComponents(material);

    % --- 표시 ---
    clf(hFig); tiledlayout(hFig,1,3,'Padding','compact','TileSpacing','compact');

    % (좌) 영상 + 재료 + 경계
    ax1=nexttile;
    image(ax1,[1 W],[1 H],bg); set(ax1,'YDir','reverse'); hold(ax1,'on');
    if TINT_MAT
      mUp=imresize(double(material),4,'nearest');
      hg=image(ax1,[minX maxX],[minY maxY],cat(3,zeros(size(mUp)),ones(size(mUp)),zeros(size(mUp))));
      set(hg,'AlphaData',0.18*mUp);
    end
    contour(ax1,Xpx,Ypx,double(material),[0.5 0.5],'c','LineWidth',2);
    axis(ax1,'image'); axis(ax1,[1 W 1 H]);
    title(ax1,sprintf('Frame %d | SIGNAL=%s | intThr=%.0f ccThr=%.2f | 재료덩어리 %d', ...
          k,SIGNAL,intThr,ccThr,nseg),'FontSize',11);

    % (중) 강도 셀맵 (어두울수록 배경)
    ax2=nexttile;
    imagesc(ax2,xv,yv,ci); set(ax2,'YDir','reverse'); hold(ax2,'on');
    contour(ax2,Xpx,Ypx,double(material),[0.5 0.5],'c','LineWidth',1.8);
    axis(ax2,'image'); axis(ax2,[minX maxX minY maxY]);
    colormap(ax2,'gray'); cb=colorbar(ax2); ylabel(cb,'cell intensity');
    title(ax2,sprintf('강도 (회색 갭<intThr=%.0f → 어둠쪽)',intThr),'FontSize',11);

    % (우) ccPeak (저상관 = 갭/배경)
    ax3=nexttile;
    imagesc(ax3,xv,yv,ccP); set(ax3,'YDir','reverse'); hold(ax3,'on');
    contour(ax3,Xpx,Ypx,double(material),[0.5 0.5],'c','LineWidth',1.8);
    axis(ax3,'image'); axis(ax3,[minX maxX minY maxY]);
    colormap(ax3,'parula'); cb3=colorbar(ax3); ylabel(cb3,'ccPeak');
    title(ax3,sprintf('ccPeak (저상관 갭<ccThr=%.2f)',ccThr),'FontSize',11);

    drawnow;
    if DO_MP4
      fr=print(hFig,'-RGBImage','-r110');
      if isempty(vidSize), vidSize=[size(fr,1) size(fr,2)]; end
      if size(fr,1)~=vidSize(1)||size(fr,2)~=vidSize(2), fr=imresize(fr,vidSize); end
      writeVideo(vw,fr);
    end
    pause(ANIM_PAUSE);
  end
  if DO_MP4, close(vw); fprintf('MP4 저장 완료\n'); end

  out.lastMaterial=material; out.frames=[t_start t_end]; out.signal=SIGNAL;
  disp('>> 검증 완료. 갭이 배경(초록 빠짐)으로 잡히는지, 변형 재료는 유지되는지 확인.');
end

%% ============================================================
%% 로컬: 셀 평균 강도 (이미지 → PIV 격자)
%% ============================================================
function ci = cell_intensity(bg,W,H,Xpx,Ypx,dx,dy)
  g = mean(double(bg),3);                                 % 그레이스케일
  hb=max(1,round(dy)); wb=max(1,round(dx));
  gm = conv2(ones(hb,1)/hb, ones(1,wb)/wb, g, 'same');    % 셀크기 박스평균(분리형)
  ci = interp2(1:W, 1:H, gm, Xpx, Ypx, 'linear', 0);      % 격자점 샘플
end

%% ============================================================
%% 로컬: 강도 임계 (multithresh 2단계 상위 → 회색 갭도 '어둠'쪽 포함)
%% ============================================================
function thr = auto_int(F, fixedThr)
  if ~isempty(fixedThr), thr=fixedThr; return; end
  rng=[min(F(:)) max(F(:))]; if rng(2)<=rng(1), thr=rng(1); return; end
  try
    lv = multithresh(F,2); thr = lv(end);    % 밝은재료 vs (회색갭+검정) 경계
  catch
    lvl=graythresh(mat2gray(F)); thr=rng(1)+lvl*(rng(2)-rng(1));
  end
end

%% ============================================================
%% 로컬: 일반 임계 (graythresh)
%% ============================================================
function thr = auto_thr(F, fixedThr)
  rng=[min(F(:)) max(F(:))];
  if ~isempty(fixedThr), thr=fixedThr;
  elseif rng(2)<=rng(1), thr=rng(1);
  else, lvl=graythresh(mat2gray(F)); thr=rng(1)+lvl*(rng(2)-rng(1)); end
end

%% ============================================================
%% 로컬: 유틸
%% ============================================================
function f = pick_cc_field(pivData)
  cand={'ccPeak','ccPeakIm','ccpeak','cc'}; f='';
  for c=1:numel(cand), if isfield(pivData,cand{c})&&~isempty(pivData.(cand{c})), f=cand{c}; return; end; end
end
function ck = get_cc(pivData,field,k)
  C=pivData.(field); if ndims(C)>=3, ck=C(:,:,min(k,size(C,3))); else, ck=C; end; ck=double(ck);
end
function n = numComponents(BW)
  n=0; if ~any(BW(:)), return; end
  try, cc=bwconncomp(BW); n=cc.NumObjects; catch, L=bwlabel(BW); n=max(L(:)); end
end
function fileList=build_file_list(pivData)
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
function bg=get_bg(fileList,pivData,idx)
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
  if ~isempty(bg)&&size(bg,3)==1, bg=cat(3,bg,bg,bg); end
end