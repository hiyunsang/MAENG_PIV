function strn = pivEffStrainPathline()
% pivEffStrainPathline — 연속 주입 입자구름으로 누적 유효변형률 필드 + 별도 패스라인(trail)
%
%   로직 = 논문 Fig.3:  dε_ij=½(∂du_i/∂x_j+∂du_j/∂x_i),  dε̄=√(2/3·dε_ij dε_ij),  ε̄=∫_pathline dε̄
%
%   [필드]   그린 직선에서 입자를 빽빽이 연속 주입 → 추적·적분 → accumarray 비닝 → smoothn 평활
%   [패스라인] 그린 직선 위 시드 NUM_PATH개를 전진 추적한 trail (pivPathlines 방식: 사망/정체/슬립)
%   [공통]   진짜 벽면=접선 슬립, 도메인 이탈=제거, 컬러범위 자동, MP4 저장 선택

  %% ===================== 파라미터 =====================
  CLIM_PERCENTILE = 100;     % 컬러 상한 (100=최댓값, 99=핫스팟 무시→더 쨍함)
  VIS_COLORMAP    = 'turbo';
  STRAIN_ALPHA    = 0.82;    % 변형률 오버레이 투명도 (1.0=최대 쨍함)
  SMOOTH_PARAM    = [];      % smoothn 평활 강도 ([]=자동, 숫자↑=더 매끈)
  COVER_DILATE    = 3;       % 재료영역 마스크 팽창(셀)
  NUM_PATH        = 12;      % 검은 패스라인 개수
  PATH_WIDTH      = 1.3;
  PATH_COLOR      = [0 0 0];
  VIDEO_FPS_DEF   = 15;
  VIDEO_MAX_FRAMES= 200;     % 영상 표시 프레임 상한(추적은 매 프레임)
  %% ==================================================

  %% 1) pivData / fileList
  if evalin('base','exist(''pivData'',''var'')'), pivData=evalin('base','pivData');
  else
      [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0),error('pivData 필요');end
      S=load(fullfile(p,f)); if isfield(S,'pivData'),pivData=S.pivData; else,fn=fieldnames(S);pivData=S.(fn{1});end
  end
  Nt=size(pivData.U,3);
  fileList=local_loadFileList(pivData,Nt);
  if isempty(fileList), error('배경 이미지를 찾지 못했습니다. fileList 를 작업공간에 두세요.'); end

  %% 2) 격자 / 마스크 / 크기
  X0=double(pivData.X); Y0=double(pivData.Y); [Ny,Nx]=size(X0);
  dx=abs(X0(1,2)-X0(1,1)); if dx==0,dx=abs(Y0(2,1)-Y0(1,1));end
  dy=abs(Y0(2,1)-Y0(1,1)); if dy==0,dy=dx;end
  minX=min(X0(:));maxX=max(X0(:)); minY=min(Y0(:));maxY=max(Y0(:));
  permMask=all(isnan(pivData.U),3);
  if isfield(pivData,'imSizeX'),imSizeX=double(pivData.imSizeX);else,imSizeX=maxX;end
  if isfield(pivData,'imSizeY'),imSizeY=double(pivData.imSizeY);else,imSizeY=maxY;end
  MAX_PTS=max(20000, round(2.5*Ny*Nx));     % 필드 입자 수 상한

  %% 3) 프레임 구간
  ad=inputdlg({'시작 프레임:',sprintf('종료 프레임(최대 %d):',Nt)},'프레임 구간',1,{'1',num2str(Nt)});
  if isempty(ad),f0=1;fE=Nt;
  else
      f0=round(str2double(ad{1}));fE=round(str2double(ad{2}));
      if isnan(f0)||f0<1,f0=1;end; if isnan(fE)||fE>Nt,fE=Nt;end; if f0>fE,[f0,fE]=deal(fE,f0);end
  end
  fprintf('>> 프레임 %d → %d\n',f0,fE);

  %% 4) 유입선 2점 클릭 → 필드 주입 시드(빽빽) + 패스라인 시드(성김)
  bg0=imread(fileList{min(f0,numel(fileList))});
  hSel=figure('Name','유입선 입력','NumberTitle','off');
  imshow(bg0,'XData',[1 imSizeX],'YData',[1 imSizeY]); set(gca,'YDir','reverse'); axis image; hold on;
  title('유입(Inlet) 직선 두 끝점 클릭 (2회) — 유동이 들어오는 상류(보통 왼쪽 세로)','FontSize',13);
  [xL,yL]=ginput(2);
  plot(xL,yL,'y-','LineWidth',2); plot(xL,yL,'ys','MarkerFaceColor','y');
  lineLen=hypot(diff(xL),diff(yL));
  Mf=max(15,round(lineLen/dx)+1);                       % 필드 주입 시드(빽빽)
  xs_in=linspace(xL(1),xL(2),Mf)'; ys_in=linspace(yL(1),yL(2),Mf)';
  sx=linspace(xL(1),xL(2),NUM_PATH)'; sy=linspace(yL(1),yL(2),NUM_PATH)';   % 패스라인 시드
  plot(sx,sy,'ro','MarkerFaceColor','r','MarkerSize',5);
  title(sprintf('필드 시드 %d개 / 패스라인 %d개',Mf,NUM_PATH)); pause(0.7); close(hSel);

  %% 5) 슬립 각도 / MP4
  angles=[5,-5,15,-15,30,-30,45,-45,60,-60,75,-75,89,-89]*(pi/180);
  doSave=strcmp(questdlg('변형률 누적 애니메이션을 MP4로 저장할까요? (아니오=재생만)','영상 저장','예','아니오','아니오'),'예');
  vw=[]; vidSize=[];
  if doSave
      fps=VIDEO_FPS_DEF; fr=inputdlg({'영상 FPS:'},'FPS',1,{num2str(VIDEO_FPS_DEF)});
      if ~isempty(fr),tmp=round(str2double(fr{1}));if ~isnan(tmp)&&tmp>0,fps=tmp;end;end
      [vn,vp]=uiputfile('*.mp4','MP4 저장','strain_pathline.mp4');
      if isequal(vn,0),doSave=false;disp('>> 저장 취소 → 재생만');
      else,vw=VideoWriter(fullfile(vp,vn),'MPEG-4');vw.FrameRate=fps;vw.Quality=100;open(vw);end
  end

  %% ===================== 추적 패스 =====================
  % 필드 입자구름 (유입선에서 시작 → 연속 주입)
  px=xs_in; py=ys_in; pE=zeros(Mf,1); feed=0;
  % 패스라인 시드 + trail 저장
  salive=true(NUM_PATH,1);
  nTot=fE-f0+1;
  trailX=nan(NUM_PATH,nTot); trailY=nan(NUM_PATH,nTot);
  trailX(:,1)=sx; trailY(:,1)=sy;

  step=max(1,ceil(nTot/VIDEO_MAX_FRAMES));
  dispF=f0:step:fE; if dispF(end)~=fE,dispF(end+1)=fE;end; nD=numel(dispF);
  EgC=cell(1,nD); fnoC=zeros(1,nD); dp=1;

  if dispF(dp)==f0
      EgC{dp}=local_cloudToField(px,py,pE,dx,dy,minX,minY,Ny,Nx,permMask,COVER_DILATE,SMOOTH_PARAM);
      fnoC(dp)=f0; dp=dp+1;
  end
  hWB=waitbar(0,'1/2  입자 주입·추적·변형률 누적 중...');
  for fi=1:nTot-1
      t=f0+fi-1;
      Ut=double(pivData.U(:,:,t)); Vt=double(pivData.V(:,:,t));
      wf=local_wallField(pivData,t,permMask,X0);
      deps=local_effIncPx(Ut,Vt,dx,dy);
      Uf=inpaint_nans(Ut,4); Vf=inpaint_nans(Vt,4);
      mU=mean(Uf(:)); if isnan(mU),mU=0;end
      mV=mean(Vf(:)); if isnan(mV),mV=0;end

      % 필드 입자구름: 누적+이류+압축+주입
      [px,py,pE,feed]=local_stepCloud(px,py,pE,feed, deps,Uf,Vf, X0,Y0,dx, wf, xs_in,ys_in, angles, minX,maxX,minY,maxY, mU,mV, MAX_PTS);
      % 패스라인 시드: 이류(+사망)
      [sx,sy,salive]=local_stepSeeds(sx,sy,salive, Uf,Vf, X0,Y0, wf, angles, minX,maxX,minY,maxY, mU,mV);
      trailX(:,fi+1)=sx; trailY(:,fi+1)=sy;

      kf=t+1;
      if dp<=nD && dispF(dp)==kf
          EgC{dp}=local_cloudToField(px,py,pE,dx,dy,minX,minY,Ny,Nx,permMask,COVER_DILATE,SMOOTH_PARAM);
          fnoC(dp)=kf; dp=dp+1;
      end
      if isvalid(hWB),waitbar(fi/max(1,nTot-1),hWB);end
  end
  if isvalid(hWB),close(hWB);end

  %% 컬러범위 자동
  allv=[]; for i=1:nD, e=EgC{i}; allv=[allv; e(~isnan(e))]; end %#ok<AGROW>
  if isempty(allv),climMax=1;
  elseif CLIM_PERCENTILE>=100,climMax=max(allv);
  else,climMax=prctile(allv,CLIM_PERCENTILE);end
  if climMax<=0,climMax=1;end
  fprintf('>> 컬러범위 자동: [0  %.3f] | 마지막 프레임 변형률 셀 %d개\n', climMax, nnz(~isnan(EgC{nD})));

  %% ===================== 렌더 패스 (오버레이 이미지) =====================
  cmap=feval(VIS_COLORMAP,256);
  hFig=figure('Name','Accumulated \epsilon_{eff} along Pathlines','Renderer','opengl','Color','w','Position',[80 80 1280 720]);
  ax=axes('Parent',hFig); hold(ax,'on');
  hBg=image('Parent',ax,'XData',[1 imSizeX],'YData',[1 imSizeY],'CData',local_toRGB(imread(fileList{min(f0,numel(fileList))})));
  [rgb0,a0]=local_fieldRGB(EgC{1},climMax,cmap,STRAIN_ALPHA);
  hField=image('Parent',ax,'XData',[minX maxX],'YData',[minY maxY],'CData',rgb0,'AlphaData',a0);
  hPath=line('Parent',ax,'XData',NaN,'YData',NaN,'Color',PATH_COLOR,'LineWidth',PATH_WIDTH);
  set(ax,'YDir','reverse','DataAspectRatio',[1 1 1]);
  xlim(ax,[1 imSizeX]); ylim(ax,[1 imSizeY]);
  colormap(ax,cmap); caxis(ax,[0 climMax]);
  cb=colorbar(ax); cb.Limits=[0 climMax]; ylabel(cb,'$\epsilon_{eff}$','Interpreter','latex','FontSize',14);
  xlabel(ax,'x [px]','FontSize',12); ylabel(ax,'y [px]','FontSize',12);

  for i=1:nD
      kf=fnoC(i); fc=kf-f0+1;
      set(hBg,'CData',local_toRGB(imread(fileList{min(kf,numel(fileList))})));
      [rgb,am]=local_fieldRGB(EgC{i},climMax,cmap,STRAIN_ALPHA);
      set(hField,'CData',rgb,'AlphaData',am);
      LX=[]; LY=[];
      for s=1:NUM_PATH, LX=[LX, trailX(s,1:fc), NaN]; LY=[LY, trailY(s,1:fc), NaN]; end %#ok<AGROW>
      set(hPath,'XData',LX,'YData',LY);
      title(ax,sprintf('Accumulated \\epsilon_{eff} along Pathlines   (Frame %d / %d)',kf,fE),'FontSize',13);
      drawnow;
      if doSave && ~isempty(vw)
          frm=print(hFig,'-RGBImage','-r150');
          if isempty(vidSize)
              h2=size(frm,1)-mod(size(frm,1),2); w2=size(frm,2)-mod(size(frm,2),2);
              vidSize=[h2 w2]; frm=frm(1:h2,1:w2,:);
          elseif size(frm,1)~=vidSize(1)||size(frm,2)~=vidSize(2)
              frm=imresize(frm,vidSize);
          end
          writeVideo(vw,frm);
      end
  end
  if doSave && ~isempty(vw),close(vw);fprintf('>> 영상 저장 완료.\n');end
  disp('>> 완료. 마지막 프레임이 최종 누적 변형률 맵입니다.');

  strn.f0=f0; strn.fE=fE; strn.climMax=climMax; strn.eps=EgC{nD};
end


%% ==================================================
%% 🛠 공통 이류: 진짜 벽면 접선 슬립 + 도메인 이탈 제거(NaN)
%% ==================================================
function [xn,yn]=local_advect(px,py, Uf,Vf, X0,Y0, wf, angles, minX,maxX,minY,maxY, mU,mV)
  if isempty(px), xn=px; yn=py; return; end
  ui=interp2(X0,Y0,Uf,px,py,'linear',mU); vi=interp2(X0,Y0,Vf,px,py,'linear',mV);
  xn=px+ui; yn=py+vi;
  oob=(xn<minX)|(xn>maxX)|(yn<minY)|(yn>maxY);
  dest=interp2(X0,Y0,wf,xn,yn,'nearest',NaN);
  hit=isnan(dest)&~oob&~isnan(xn); hi=find(hit);
  if ~isempty(hi)
      spd=sqrt(ui(hi).^2+vi(hi).^2); a0=atan2(vi(hi),ui(hi));
      xc=px(hi); yc=py(hi); xr=xc; yr=yc; res=false(numel(hi),1);
      for a=angles
          if all(res),break;end
          un=~res; at=a0(un)+a;
          xt=xc(un)+cos(at).*spd(un); yt=yc(un)+sin(at).*spd(un);
          ok=~isnan(interp2(X0,Y0,wf,xt,yt,'nearest',NaN)) & xt>minX&xt<maxX&yt>minY&yt<maxY;
          gi=find(un); gv=gi(ok); xr(gv)=xt(ok); yr(gv)=yt(ok); res(gv)=true;
      end
      xn(hi)=xr; yn(hi)=yr;
  end
  xn(oob)=NaN; yn(oob)=NaN;     % 이탈 = 제거
end


%% ==================================================
%% 🛠 필드 입자구름 한 스텝: 변형률 누적 + 이류 + 압축 + 연속 주입
%% ==================================================
function [px,py,pE,feed]=local_stepCloud(px,py,pE,feed, deps,Uf,Vf, X0,Y0,dx, wf, xs_in,ys_in, angles, minX,maxX,minY,maxY, mU,mV, MAX_PTS)
  % 변형률 증분 누적 (현재 위치)
  dpp=interp2(X0,Y0,deps,px,py,'linear',NaN); dpp(isnan(dpp))=0; pE=pE+dpp;
  % 이류
  [xn,yn]=local_advect(px,py, Uf,Vf, X0,Y0, wf, angles, minX,maxX,minY,maxY, mU,mV);
  px=xn; py=yn;
  % 압축(이탈 제거)
  keep=~isnan(px); px=px(keep); py=py(keep); pE=pE(keep);
  % 연속 주입 (feed: 유입속도 누적이 dx 넘으면 한 줄 주입)
  Uanc=interp2(X0,Y0,Uf,xs_in,ys_in,'linear',mU); Vanc=interp2(X0,Y0,Vf,xs_in,ys_in,'linear',mV);
  spd_in=hypot(mean(Uanc),mean(Vanc)); if isnan(spd_in)||spd_in<=0,spd_in=abs(mU);end; if spd_in==0,spd_in=1;end
  feed=feed+spd_in; nInj=0;
  while feed>=dx && nInj<5
      feed=feed-dx; nInj=nInj+1;
      px=[px;xs_in]; py=[py;ys_in]; pE=[pE;zeros(numel(xs_in),1)];
  end
  % 입자 수 상한(가장 오래된=하류 제거)
  if numel(px)>MAX_PTS, d=numel(px)-MAX_PTS; px(1:d)=[]; py(1:d)=[]; pE(1:d)=[]; end
end


%% ==================================================
%% 🛠 패스라인 시드 한 스텝 (이류 + 사망)
%% ==================================================
function [sx,sy,salive]=local_stepSeeds(sx,sy,salive, Uf,Vf, X0,Y0, wf, angles, minX,maxX,minY,maxY, mU,mV)
  act=salive & ~isnan(sx);
  if ~any(act), return; end
  [xn,yn]=local_advect(sx(act),sy(act), Uf,Vf, X0,Y0, wf, angles, minX,maxX,minY,maxY, mU,mV);
  newx=sx; newy=sy; newx(act)=xn; newy(act)=yn;
  died=act & isnan(newx); salive(died)=false;   % 이탈 시드 사망 → trail 종료
  sx=newx; sy=newy;
end


%% ==================================================
%% 🛠 입자구름 → 격자 변형률 (비닝 + smoothn 평활 + 재료영역 마스크)
%% ==================================================
function Eg=local_cloudToField(px,py,pE, dx,dy,minX,minY,Ny,Nx,permMask,coverDil,smoothParam)
  ok=~isnan(px)&~isnan(py)&~isnan(pE); px=px(ok);py=py(ok);pe=pE(ok);
  Eg=nan(Ny,Nx);
  if isempty(px), return; end
  ci=round((px-minX)/dx)+1; ri=round((py-minY)/dy)+1;
  inb=ci>=1&ci<=Nx&ri>=1&ri<=Ny; if ~any(inb),return;end
  ci=ci(inb); ri=ri(inb); pe=pe(inb);
  Eb=accumarray([ri,ci], pe, [Ny Nx], @mean, NaN);        % 칸별 평균(빈칸 NaN)
  % 재료영역 마스크(입자 셀 + 팽창)
  hasPt=false(Ny,Nx); hasPt(sub2ind([Ny Nx],ri,ci))=true;
  cover=imdilate(hasPt, strel('disk',coverDil));
  % smoothn: 구멍 메움 + 평활 (NaN 자동 처리)
  try
      if isempty(smoothParam), Es=smoothn(Eb); else, Es=smoothn(Eb,smoothParam); end
  catch
      Es=Eb;
  end
  if iscell(Es), Es=Es{1}; end
  Eg=Es; Eg(~cover)=NaN; Eg(permMask)=NaN;
end


%% ==================================================
%% 🛠 변형률 필드 → RGB + 투명도
%% ==================================================
function [rgb,amask]=local_fieldRGB(Eg,climMax,cmap,alphaVal)
  if isempty(Eg), Eg=NaN; end
  [ny,nx]=size(Eg);
  En=Eg/climMax; En(En<0)=0; En(En>1)=1;
  idx=round(En*(size(cmap,1)-1))+1; idx(isnan(idx))=1; idx=min(max(idx,1),size(cmap,1));
  R=reshape(cmap(idx,1),[ny nx]); G=reshape(cmap(idx,2),[ny nx]); B=reshape(cmap(idx,3),[ny nx]);
  rgb=cat(3,R,G,B);
  amask=alphaVal*double(~isnan(Eg));
end


%% ==================================================
%% 🛠 유효변형률 증분 (논문 Fig.3) / 미분 / 벽면 / fileList / RGB
%% ==================================================
function deps=local_effIncPx(U,V,dx,dy)
  U(isnan(U))=NaN; V(isnan(V))=NaN;
  [dUdx,dUdy]=local_nanGradient(U,dx,dy);
  [dVdx,dVdy]=local_nanGradient(V,dx,dy);
  exy=0.5*(dUdy+dVdx);
  deps=sqrt((2/3)*(dUdx.^2 + dVdy.^2 + 2*exy.^2));
end

function [dFdx,dFdy]=local_nanGradient(F,dx,dy)
  [Ny,Nx]=size(F); dFdx=nan(Ny,Nx); dFdy=nan(Ny,Nx);
  for i=1:Ny
      for j=1:Nx
          if isnan(F(i,j)),continue;end
          hl=(j>1)&&~isnan(F(i,j-1)); hr=(j<Nx)&&~isnan(F(i,j+1));
          if hl&&hr,dFdx(i,j)=(F(i,j+1)-F(i,j-1))/(2*dx);
          elseif hl,dFdx(i,j)=(F(i,j)-F(i,j-1))/dx;
          elseif hr,dFdx(i,j)=(F(i,j+1)-F(i,j))/dx; end
          hu=(i>1)&&~isnan(F(i-1,j)); hd=(i<Ny)&&~isnan(F(i+1,j));
          if hu&&hd,dFdy(i,j)=(F(i+1,j)-F(i-1,j))/(2*dy);
          elseif hu,dFdy(i,j)=(F(i,j)-F(i-1,j))/dy;
          elseif hd,dFdy(i,j)=(F(i+1,j)-F(i,j))/dy; end
      end
  end
end

function wf=local_wallField(pivData,t,wall_global,X0)
  if isfield(pivData,'Status')
      sidx=min(t,size(pivData.Status,3));
      wn=logical(bitget(uint8(pivData.Status(:,:,sidx)),1));
  else, wn=wall_global; end
  wf=zeros(size(X0)); wf(wn)=NaN;
end

function fl=local_loadFileList(pivData,Nt)
  fl={};
  if evalin('base','exist(''fileList'',''var'')'), fl=evalin('base','fileList');
  elseif isfield(pivData,'imagePath')&&exist(pivData.imagePath,'dir')
      for ext={'*.png','*.bmp','*.tif','*.tiff','*.jpg'}
          D=dir(fullfile(pivData.imagePath,ext{1}));
          if ~isempty(D),[~,si]=sort({D.name});fl=fullfile(pivData.imagePath,{D(si).name});break;end
      end
  elseif isfield(pivData,'imFilename2')&&iscell(pivData.imFilename2), fl=pivData.imFilename2;
  elseif isfield(pivData,'imFilename1')&&iscell(pivData.imFilename1), fl=pivData.imFilename1; end
  if iscell(fl)&&numel(fl)>Nt, fl=fl(1:Nt); end
end

function I=local_toRGB(I)
  if size(I,3)==1, I=repmat(I,[1 1 3]); end
  if ~isa(I,'uint8'), I=im2uint8(I); end
end