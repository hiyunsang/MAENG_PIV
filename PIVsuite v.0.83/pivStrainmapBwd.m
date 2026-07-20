function eff = pivStrainmapBwd(pivData)
% pivStrainmapBwd — 역방향 "현재 형상" 누적 유효변형률 + 유맥선(Streakline) 오버레이
% ----------------------------------------------------------------------------
%  변형률 (배경 색):
%   1) 마지막 프레임 t_end 격자점에서 출발 (현재 형상 = 변형된 자리)
%   2) 과거로 추적(Px -= U) 하며 경로 따라 dε̄ 누적
%   3) 결과를 t_end 격자에 그대로 매핑 → 규칙 격자라 contourf 가 부드러움
%   ★ 미분 전 smoothn 으로 노이즈 억제, 벽 NaN 보존
%
%  [v2 수정] (1) 노이즈 바닥(deadband): 균일/강체 유동의 노이즈 누적 차단
%            (2) 구멍 메우기: t_end NaN/0 내부 노드 inpaint(진짜 벽은 NaN 유지)
%  [v3 수정] (3) 유맥선 시드: 선 2점 클릭 → 균등 등분 배치(SEED_MODE='line')
%
%  유맥선 (검은 선):
%   • 같은 프레임 구간 [t_start, t_end] 에서 매 프레임 입자를 연속 주입(전진 추적)
%   • t_end 시점의 유맥선 형상을 검은 선으로 변형률 맵 위에 겹쳐 그림
%   • Coast Limit(관성 돌파)로 마스크/벽 통과 방지 — pivStreaklines 로직 이식
%
%  좌표: 픽셀(영상 오버레이 기준)
%  실행: 인자 없이 F5  또는  eff = pivStrainmapBwd(pivData)
% ----------------------------------------------------------------------------

  %% ===== 파라미터 (변형률) =====
  t_start=[]; t_end=[]; ASK_FRAMES=true;
  SMOOTH_VEL=true;
  CMAP='jet'; CLIM_MAX=[];      % Image 2처럼 고정하려면 예: 10
  MAP_ALPHA=0.85;
  DO_ROI=false;                 % getrect 2차 ROI 렌더

  %% ===== 파라미터 (노이즈 바닥 / 구멍 보정) =====
  SMOOTH_S       = [];          % 미분 전 smoothn 강도([]=자동GCV, 숫자 클수록 매끈)
  EPS_RATE_FLOOR = 'auto';      % 프레임당 노이즈 바닥: 'auto' | 절대값(>0) | 0(off)
  MED_FACTOR     = 2.0;         % 'auto'일 때 floor = MED_FACTOR×median(증분).
                                %   균일영역 더 깨끗이→값↑(예 3), 밴드 더 살리려면→값↓(예 1.5)
  FILL_HOLES     = true;        % 맵 내부 구멍(계산실패/순간0) 메우기(진짜 벽은 유지)
  FILL_METHOD    = 'inpaint';   % 'inpaint'(국소,밴드 보존) | 'smoothn'(보간+스무딩)
  SMOOTH_MAP     = false;       % 채운 뒤 최종 맵 전체 한 번 더 스무딩(밴드 흐려질 수 있음)

  %% ===== 파라미터 (유맥선 오버레이) =====
  DO_STREAK     = true;         % 검은 유맥선 오버레이 on/off
  SEED_MODE     = 'line';       % 'line'(선 2점 클릭→균등 등분) | 'click'(점 직접 클릭)
  N_SEED        = 8;            % 유맥선 개수(line:등분 점수 / click:클릭 점수)
  MAX_COAST     = 3;            % NaN 관성 유지 프레임 수(이후 정지)
  STREAK_INTERP = 'linear';     % 속도 보간법('linear' 권장 / 원본 동작은 'nearest')
  STREAK_LW     = 1.3;          % 유맥선 선 두께
  STREAK_COLOR  = 'k';          % 유맥선 색(요청: 검정)

  %% ===== 로드 =====
  if nargin<1||isempty(pivData)
    if evalin('base','exist(''pivData'',''var'')'), pivData=evalin('base','pivData');
    else, [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0), eff=[]; return; end
      S=load(fullfile(p,f)); fn=fieldnames(S); pivData=S.(fn{1}); end
  end
  Nt=size(pivData.U,3);
  if isempty(t_start),t_start=1; end; if isempty(t_end),t_end=Nt; end
  if ASK_FRAMES
    a=inputdlg({'시작 프레임','끝 프레임(현재형상 기준)'},'프레임 범위',1,{num2str(t_start),num2str(t_end)});
    if ~isempty(a), t_start=str2double(a{1}); t_end=str2double(a{2}); end
  end
  t_start=max(1,min(Nt,round(t_start))); t_end=max(t_start,min(Nt,round(t_end)));

  Xpx=double(pivData.X); Ypx=double(pivData.Y); [ny,nx]=size(Xpx);
  dx=double(pivData.iaStepX); dy=double(pivData.iaStepY);
  minX=min(Xpx(:));maxX=max(Xpx(:));minY=min(Ypx(:));maxY=max(Ypx(:));

  %% ===== 시드 = t_end 격자(유효영역) =====
  Ue=double(pivData.U(:,:,t_end)); Ve=double(pivData.V(:,:,t_end));
  vmE=~isnan(Ue)&~(Ue==0&Ve==0);
  Px=Xpx(vmE); Py=Ypx(vmE); Eps=zeros(size(Px));
  fprintf('역방향 변형률(현재형상): 프레임 %d→%d, 격자점 %d개\n',t_end,t_start,numel(Px));

  %% ===== 역방향 추적 + 누적 =====
  for k=t_end:-1:t_start
    Uk=double(pivData.U(:,:,k)); Vk=double(pivData.V(:,:,k));
    dEbar=incr_eff_strain(Uk,Vk,dx,dy,SMOOTH_VEL,SMOOTH_S);
    dEbar=apply_strain_floor(dEbar,EPS_RATE_FLOOR,MED_FACTOR);   % ★(1) 노이즈 바닥
    dEp=interp2(Xpx,Ypx,dEbar,Px,Py,'linear',NaN);
    add=~isnan(dEp); Eps(add)=Eps(add)+dEp(add);
    if k==t_start, break; end
    Uf=inpaint_nans(Uk,4); Vf=inpaint_nans(Vk,4);
    up=interp2(Xpx,Ypx,Uf,Px,Py,'linear',0); vp=interp2(Xpx,Ypx,Vf,Px,Py,'linear',0);
    Px=max(min(Px-up,maxX),minX); Py=max(min(Py-vp,maxY),minY);    % ★ 역방향
  end

  %% ===== 격자 복귀 (현재형상 = t_end 격자) + 구멍 메우기 =====
  E2=nan(ny,nx); E2(vmE)=Eps;

  % 진짜 벽: 전 프레임 공통 마스크/0 (= 공구/장애물, 비워 둠)
  tm=true(ny,nx);
  for k=t_start:t_end
    Uk=double(pivData.U(:,:,k)); Vk=double(pivData.V(:,:,k));
    tm=tm&((Uk==0&Vk==0)|isnan(Uk));
  end

  eff.epsRaw=E2; eff.epsRaw(tm)=NaN;                 % 원본(구멍 포함) 보관

  % ★(2) 채울 대상 = NaN 이지만 진짜 벽은 아닌 곳(계산실패/순간 0)
  holeMask = isnan(E2) & ~tm;
  if FILL_HOLES && any(holeMask(:))
    if strcmpi(FILL_METHOD,'smoothn'), Efill=smoothn(E2);
    else,                              Efill=inpaint_nans(E2,4); end
    E2(holeMask)=Efill(holeMask);                    % 구멍만 채움(원 유효값 보존)
    fprintf('맵 구멍 %d개 채움 (method=%s).\n', nnz(holeMask), FILL_METHOD);
  end
  if SMOOTH_MAP                                      % (옵션) 최종 맵 전체 스무딩
    E2s=smoothn(E2); keep=~tm; E2(keep)=E2s(keep);
  end
  E2(tm)=NaN;                                        % 진짜 벽 다시 비움

  eff.eps=E2; eff.X=Xpx; eff.Y=Ypx; eff.frames=[t_start t_end]; eff.config='current(backward)';

  %% ===== 렌더 (t_end 배경) =====
  fileList=build_file_list(pivData); bg=get_bg(fileList,pivData,t_end);
  if isfield(pivData,'imSizeX'),W=pivData.imSizeX;else,W=size(bg,2);end
  if isfield(pivData,'imSizeY'),H=pivData.imSizeY;else,H=size(bg,1);end

  hMain=figure('Name','Backward Strain + Streaklines (current config snapshot)','Color','w');
  if ~isempty(bg), image([1 W],[1 H],bg); end
  set(gca,'YDir','reverse'); hold on;
  axMain=gca;                                      % ★ 유맥선 오버레이용 축 핸들
  [~,hc]=contourf(Xpx,Ypx,E2,80,'LineStyle','none'); try,alpha(hc,MAP_ALPHA);catch,end
  colormap(CMAP);
  if ~isempty(CLIM_MAX),set(gca,'CLim',[0 CLIM_MAX]);
  else, vv=E2(~isnan(E2)); if ~isempty(vv),set(gca,'CLim',[0 max(pctl99(vv),eps)]); end; end
  cb=colorbar; ylabel(cb,'$\bar{\epsilon}$ (effective strain)','Interpreter','latex');
  axis image; if ~isempty(bg), axis([1 W 1 H]); end
  title(sprintf('역방향 누적 변형률 (현재 형상)   Frame %d→%d',t_start,t_end),'FontSize',13);

  %% ===== 유맥선(검은 선) 오버레이 =====
  if DO_STREAK
    xs=[]; ys=[];
    if strcmpi(SEED_MODE,'line')
      %% --- 모드 A: 선을 그려 등분 ---
      a2=inputdlg({'유맥선 개수(라인 등분 점수, ≥2)'},'유맥선 Seed',1,{num2str(N_SEED)});
      if ~isempty(a2)
        nSeed=max(2,round(str2double(a2{1})));        % 선 등분이라 최소 2개
        figure(hMain);
        title(axMain,'시드 라인: 시작점 → 끝점 2곳을 클릭하세요','FontSize',13);
        [lx,ly]=ginput(2);                            % 라인 양 끝점
        if numel(lx)>=2
          plot(axMain,lx(1:2),ly(1:2),'--','Color',STREAK_COLOR,'LineWidth',0.8); % 시드 라인 참조
          tt=linspace(0,1,nSeed)';                    % 양 끝점 포함 균등 등분
          xs=lx(1)+tt*(lx(2)-lx(1));
          ys=ly(1)+tt*(ly(2)-ly(1));
        end
      end
    else
      %% --- 모드 B: 점 직접 클릭 ---
      a2=inputdlg({'유맥선 주입점 개수'},'유맥선 Seed',1,{num2str(N_SEED)});
      if ~isempty(a2)
        nSeed=max(1,round(str2double(a2{1})));
        figure(hMain);
        title(axMain,sprintf('유맥선 주입점 %d개를 클릭하세요 (이미지 안쪽)',nSeed),'FontSize',13);
        [xs,ys]=ginput(nSeed);
      end
    end

    if ~isempty(xs)
      xs=max(min(xs,maxX),minX); ys=max(min(ys,maxY),minY);   % 격자 경계로 클램프
      fprintf('유맥선 추적: 주입점 %d개, 프레임 %d→%d\n',numel(xs),t_start,t_end);
      [sX,sY]=streaklines_to_end(pivData,xs,ys,t_start,t_end,MAX_COAST,STREAK_INTERP);
      for i=1:numel(xs)
        plot(axMain,sX(i,:),sY(i,:),'-','Color',STREAK_COLOR,'LineWidth',STREAK_LW);
      end
      plot(axMain,xs,ys,'.','Color',STREAK_COLOR,'MarkerSize',10);   % 주입점 표시
      eff.streakX=sX; eff.streakY=sY; eff.streakSeeds=[xs ys];
    end
    title(axMain,sprintf('역방향 누적 변형률 + 유맥선   Frame %d→%d',t_start,t_end),'FontSize',13);
  end

  %% ===== (선택) ROI 2차 =====
  if DO_ROI
    disp('>> 확대할 ROI 사각형을 드래그하세요...');
    r=getrect(gcf); roi=[r(1) r(1)+r(3) r(2) r(2)+r(4)];
    m=(Xpx>=roi(1)&Xpx<=roi(2)&Ypx>=roi(3)&Ypx<=roi(4));
    Ef=E2; Ef(~m)=NaN;
    figure('Color','w'); if ~isempty(bg), image([1 W],[1 H],bg); end
    set(gca,'YDir','reverse'); hold on;
    [~,hc2]=contourf(Xpx,Ypx,Ef,80,'LineStyle','none'); try,alpha(hc2,1.0);catch,end
    colormap(CMAP); if ~isempty(CLIM_MAX),set(gca,'CLim',[0 CLIM_MAX]); end
    colorbar; axis image; if ~isempty(bg), axis([1 W 1 H]); end
    title('ROI 변형률 (현재 형상)','FontSize',13);
  end
  disp('>> 역방향 스냅샷 + 유맥선 완료.');
end

%% ============================================================
%% 로컬: 프레임당 노이즈 바닥(deadband) — 균일 유동 누적 방지
%% ============================================================
function dE = apply_strain_floor(dE, spec, medFactor)
% floor 미만의 증분 변형률을 0 으로(하드 임계). 균일/강체 영역의 노이즈가
% 매 프레임 양(+)으로 쌓이는 것을 차단. 밴드는 floor 이상이라 전액 보존.
  if isempty(spec), return; end
  if isnumeric(spec)
    if spec<=0, return; end
    fl = double(spec);                         % 절대 임계
  else                                          % 'auto'
    v = dE(~isnan(dE));
    if isempty(v), return; end
    fl = medFactor * median(v);                 % 배경(중앙값) 기준 임계
  end
  dE(dE < fl) = 0;
end

%% ============================================================
%% 로컬: 유맥선 전진 추적 (t_end 시점 형상 반환)
%% ============================================================
function [posX,posY]=streaklines_to_end(pivData,xs,ys,t_start,t_end,maxCoast,method)
% 연속 주입식 유맥선을 t_start→t_end 전진 추적.
% 반환 posX,posY : [Ns x nF], 각 행=주입점, 열=주입시점(오래된→최신=주입점),
%                  값 = t_end 시점에서의 입자 위치(=유맥선 한 가닥).
% pivStreaklines 의 Coast Limit 로직을 시드 방향으로 벡터화.
  X=double(pivData.X); Y=double(pivData.Y);
  minX=min(X(:)); maxX=max(X(:)); minY=min(Y(:)); maxY=max(Y(:));
  xs=xs(:); ys=ys(:); Ns=numel(xs);
  nF=t_end-t_start+1;                          % 주입 시점 개수
  posX=nan(Ns,nF); posY=nan(Ns,nF);
  prev_u=zeros(Ns,nF); prev_v=zeros(Ns,nF);    % 각 (주입점,주입시점) 별 직전 속도
  coast =zeros(Ns,nF);                         % 각 입자별 연속 NaN 카운트

  for t=t_start:t_end
    j=t-t_start+1;                             % 현재 주입 컬럼
    posX(:,j)=xs; posY(:,j)=ys;                % 신규 입자 주입
    if t==t_end, break; end                    % 마지막 프레임은 이동 없이 종료

    U=double(pivData.U(:,:,t));                 % 원본 속도(NaN 유지 → 벽 판정용)
    V=double(pivData.V(:,:,t));

    for p=1:j                                  % 활성 입자(주입시점 1~j) 일괄 이동
      xc=posX(:,p); yc=posY(:,p);              % Ns×1 (이동 전 위치)
      u=interp2(X,Y,U,xc,yc,method);           % 범위/마스크 밖이면 NaN
      v=interp2(X,Y,V,xc,yc,method);

      bad=isnan(u)|isnan(v);                   % 벽/마스크 후보
      coast(bad,p)=coast(bad,p)+1;             % 카운트 증가
      coast(~bad,p)=0;                         % 정상이면 리셋
      useC = bad & (coast(:,p)<=maxCoast);     % 관성 유지 구간
      stop = bad & (coast(:,p)> maxCoast);     % 장애물 판정 → 정지
      good = ~bad;                             % 정상 영역

      u(useC)=prev_u(useC,p); v(useC)=prev_v(useC,p);          % 관성(직전 속도)
      u(stop)=0;             v(stop)=0;                        % 완전 정지
      prev_u(stop,p)=0;      prev_v(stop,p)=0;
      prev_u(good,p)=u(good); prev_v(good,p)=v(good);          % 정상: 속도 갱신

      xn=xc+u; yn=yc+v;                         % 전진(+ displacement)
      posX(:,p)=min(max(xn,minX),maxX);         % 경계 제한
      posY(:,p)=min(max(yn,minY),maxY);
    end
  end
end

%% ============================================================
%% 로컬: 증분 유효변형률 (von Mises 등가, pivEffStrain 동일식)
%% ============================================================
function dE = incr_eff_strain(U,V,dx,dy,doSmooth,smoothS)
  if nargin<6, smoothS=[]; end
  rawNaN=isnan(U);
  if doSmooth, Uf=smoothn(U,smoothS); Vf=smoothn(V,smoothS);   % smoothS=[]면 자동(GCV)
  else,        Uf=inpaint_nans(U,4);  Vf=inpaint_nans(V,4);  end
  [dUx,dUy]=gradient(Uf,dx,dy);
  [dVx,dVy]=gradient(Vf,dx,dy);
  exy=0.5*(dUy+dVx);
  dE=sqrt((2/3)*(dUx.^2 + dVy.^2 + 2*exy.^2));
  dE(rawNaN)=NaN;
end

%% ============================================================
%% 로컬: 배경 파일/이미지 유틸
%% ============================================================
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

function v=pctl99(x)
  x=sort(x(:)); if isempty(x), v=eps; return; end
  v=x(max(1,round(0.99*numel(x))));
end