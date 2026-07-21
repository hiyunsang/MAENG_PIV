function out = MAENG_StrainmapFwd(pivData)
% =============================================================================
% MAENG_StrainmapFwd — 정방향(Forward) 시간진화 누적 유효변형률 맵 (현재 형상 기준)
% =============================================================================
% [이 코드가 하는 일 — 다음 세션의 Claude/사용자를 위한 요약]
%   절삭(orthogonal cutting) 고속촬영 PIV 결과(pivData)에서, 좌측 유입선에
%   가상 입자를 심고 매 프레임 실측 속도장으로 이류(advection)시키면서
%   경로 증분 유효변형률 dε̄ = sqrt((2/3)(εxx²+εyy²+2εxy²)) 를 누적한다.
%   누적값 ε̄ 을 입자의 '현재 위치'에서 scatteredInterpolant로 보간해
%   현재 형상(칩 포함) 위에 컬러 컨투어로 그린다. (Harzallah 2018 Image 2 스타일)
%
% [★ 색칠 영역 로직 — 단순·확정판 (사용자 지시로 확정, 변경 금지 사항)]
%   "등분 streakline 여러 개를 죽죽 긋고, 맨 위 streakline을 경계로 삼아
%    그 아래 면적만 색칠한다. 맨 위 선은 NaN을 만나도 슬라이딩이 잘 되어야 한다."
%   구현:
%   1) 내부 '마스크선' N_MASK개(등분, 비표시)와 화면 '표시선'(SHOW_MODE로
%      개수/위치 선택: ndiv/click/list)을 분리해 매 프레임 streak 점 주입.
%      마스크 경계 품질은 마스크선이 보장, 화면의 선 개수는 자유 조절.
%   2) 모든 streak 점의 이류 = strain 입자와 '완전히 동일한' advect_real
%      (실데이터 linear→nearest, 정체 정지, 목적지 NaN이면 각도탐색 슬라이드
%       0,±5°..±85° — MAENG_Pathlines.m과 동일 철학)
%   3) 속도장은 '경계확장 실데이터장(Uex/Vex)': 유효 실측 셀에서 BND_EXT칸
%      이내의 NaN(자유표면 위 공기)에만 최근접 실측 속도를 bwdist로 복사.
%      → 맨 위 streak 점이 자유표면 위에 있어도 바로 아래 재료의 '실제'
%        속도를 받아 표면을 밀착 추적. 깊은 공기·공구는 NaN 유지 → 슬라이드/정지.
%   4) 색칠 마스크 = ★인접 마스크선 스트립 합집합: 쌍(i,i+1)마다
%      [i선 궤적]+[i+1선 궤적] 스트립 폴리곤을 poly2mask 후 OR, imfill 정리.
%      (한 개 거대 폴리곤 방식은 even-odd 자기교차로 칩 상단이 깜빡이며
%       사라지는 버그 — 과거 실패 기록 참조. 스트립 방식이 이를 해결)
%      결과적으로 맨 위 마스크선 '아랫부분'만 색칠됨.
%   5) ★ 시드 스냅(SNAP_MAX): 클릭한 자유표면은 보통 PIV 유효 데이터
%      최상단보다 1~2칸 위(표면 걸친 IA는 상관 실패). BND_EXT 확장이 못
%      닿으면 시드가 속도 NaN→정체→속도0→슬라이드 실패로 '영구 고착'되고,
%      맨 위 선이 점 하나가 되어 poly2mask 닫힘 변이 시드→선단 '직선'으로
%      나타남(= 반복 발생했던 직선 증상의 최종 원인). 주입 시점에 시드를
%      최근접 유효 셀로 스냅해 출발을 보장.
%   6) ★ 폴리라인 평활(STREAK_SMOOTH): 렌더/마스크 직전에만 movmean 적용.
%      이류용 원본 좌표는 불변 → 누적 왜곡 없음. 표시선과 색칠 경계에
%      동일한 평활 좌표 사용 → '그려진 선 = 경계' 일치.
%   7) ★ 장기 프레임(수백~1000+) 랙 대책: 라그랑주 적분은 프레임당 편향이
%      한 방향으로 누적됨(칩이 위인데 변형장이 아래 = 랙). 원인 =
%      ①NaN 정체 프레임(변위 손실, NaN 많은 칩에서 최다)
%      ②경계/전단대 PIV 속도 과소평가(부분 IA·큰 구배·평활)
%      ③슬라이드 cosθ 손실(자유표면 비물리) ④1차 오일러 곡률 오차.
%      대책 = NSUB 서브스텝(①④ 완화), SLIDE_FULLSPEED(③ 제거, streak 전용),
%      DIAG_EVERY 정체율 출력(①/② 판별: 정체율 낮은데 랙이면
%      PIV 데이터 편향이라 코드로 못 고침 — 논문에 한계로 명시 권장).
%   8) ★ 재료 내부 NaN 채움(FILL_GAP): NaN 정체(원인①)의 주범은
%      '재료에 파묻혔지만 공기와 연결된' 칩 가장자리 NaN 만(灣) —
%      imclearborder가 못 잡음. 유효장을 imclose(FILL_GAP)로 닫아 폭
%      ≤2×FILL_GAP 틈만 추가 채움. ⚠ NaN '전부' 채우기(무차별 inpaint)는
%      금지: 공기에 가상유동 생성 + 실공극 가로지르는 가짜 유동/변형률
%      (과거 실패 기록 참조). 분절 칩 실공극은 채우면 안 되므로 FILL_GAP은
%      공극 폭보다 작게. 근본 해법은 ccPeak 기반 재료 마스크
%      (MAENG_MaterialMaskCheck.m) 통합 — 추후 작업.
%   9) ★ 노이즈 정류 보정(EPS_MODE): dε̄=√(제곱합)은 양수 정의라 강체
%      평행이동/단순 상승 중에도 PIV 노이즈 구배가 매 프레임 양의 증분으로
%      정류 누적됨(1000프레임 = Nf×노이즈바닥의 가짜 변형률). 회전은 dε̄
%      식에서 이미 제외라 범인 아님. 보정: 강체 영역이 면적 대부분인 점을
%      이용해 median(dε̄)≈노이즈 바닥으로 매 프레임 자동 추정, 바닥 미만
%      증분은 gate(0 처리). 바닥값은 DIAG_EVERY 출력으로 확인 가능.
%  10) ⚠ [미해결] 재료/배경 경계 줄무늬: 정적 배경은 NaN이 아니라
%      '유효한 ~0 벡터'로 측정됨(정지 자기상관, median test도 통과) →
%      재료↔배경 속도 불연속이 중앙차분에 잡혀 경계 한 줄에 가짜 변형률.
%      [시도·철회] V_STATIC(전 프레임 |V|<문턱 셀을 벽으로 흡수) —
%      정체점/BUE/저속 재료를 배경으로 오분류할 구조적 위험으로 롤백함.
%      속도 크기만으로는 '정지 배경'과 '정지 재료(BUE)'를 구분 불가.
%      올바른 해법 = ccPeak 기반 프레임별 재료 마스크(MAENG_MaterialMaskCheck.m)
%      를 frame_wall에 통합해 재료/배경을 상관품질로 구분 — 추후 작업.
%      임시 완화: EPS_MODE gate가 줄무늬 일부를 흡수(바닥 이하 성분만).
%  11) ★ 스냅샷/사후 추출(REC_EVERY + ASK_EXTRACT): 실행 중 REC_EVERY
%      프레임마다 입자·streakline 상태를 out.snap에 기록. 실행이 끝나면
%      추출 대화상자가 자동으로 떠서 [프레임 / CLim 상한 / 저장 파일명]을
%      물어보고 즉시 재렌더(취소할 때까지 반복, 파일명 입력 시 600dpi
%      PNG + 벡터 PDF 저장, 재시뮬레이션 불필요).
%      나중에 다시 뽑을 때: out이 workspace에 있으면 extractStrainmap.m
%      (명령창 복붙용 스크립트)로 동일 추출 가능.
%      추출 가능한 프레임 목록 = out.snapFrames.
%   ※ 과거 시도와 실패 원인(재발 방지용 기록):
%      - streakline을 inpaint 완전채움장으로 이류 → 가상유동 오염, 경계 어긋남
%      - 별도 경계 pathline 입자(실데이터만) → 자유표면 입자 고착 → 직선화
%      - inpaint 폴백 → 칩/시편 혼합 가상속도로 대각선 드리프트 → 직선화
%      - 시드 미스냅 → 공기 위 시드 영구 고착 → 시드-선단 직선(닫힘 변)
%      - 단일 폴리곤 마스크 → poly2mask even-odd + 자기교차(맨위선 접힘,
%        선단 뒤처짐 교차) → 칩 상단 맵이 있다가 사라지는 깜빡임
%      ⇒ 최종: streakline + 슬라이드 + 경계확장 실데이터장 + 시드 스냅
%              + 스트립 합집합 마스크 (이 파일)
%
% [입력]  pivData (인자 생략 시 base workspace에서 자동 로드, 없으면 파일선택)
%         필요 필드: X,Y,U,V(:,:,Nt), iaStepX/Y, (선택) Status, imSizeX/Y,
%                    imFilename1/2 또는 imagePath. 배경은 fileList 우선.
% [출력]  out: strain 입자 위치/누적변형률, streakline 궤적(spX/spY), 설정 요약
% [좌표]  픽셀 단위(영상 오버레이 기준), YDir reverse
% [실행]  인자 없이 F5 또는 out = MAENG_StrainmapFwd(pivData)
%
% [프레임 루프 개요]
%   ① frame_wall: Status bit1(벽) ∪ persistWall(전 프레임 NaN/0) — 변형률용
%      frame_toolwall: Status bit1만(공기 제외) — Uex 확장 금지 영역
%   ② Ufill/Vfill = inpaint 전체 채움(변형률 미분용)
%      Ua/Va = 내부 cc구멍만 채운 실데이터장(이류용)
%      Uex/Vex = Ua/Va + 경계 BND_EXT칸 최근접 확장(streak/strain 이류 공용)
%   ③ 좌측 유입선 연속 주입(신선 strain 입자 ε=0, streak 점 1개/선)
%   ④ dε̄ 계산(벽 NaN, NaN-aware 편측차분) → 입자 현재 위치에서 샘플·누적
%   ⑤ 렌더: scatter 보간 → 맨위 streakline 폴리곤 마스크 → 공구 제거 → contourf
%   ⑥ 이류: strain 입자 & 모든 streak 점 — 동일 advect_real(Uex/Vex)
% =============================================================================

  %% ===== 사용자 파라미터 =====
  t_start = [];  t_end = [];     % 빈 값 = 1 / Nt
  ASK_FRAMES = true;

  SEED_REF  = 2;                 % strain 입자 시드/주입 조밀도 (PIV 격자 대비 /축)
  DISP_REF  = 2;                 % 렌더/마스크 격자 조밀도. 경계 매끈하게 하려면 ↑(3)
  SMOOTH_VEL= 1;                 % 변형률 속도장 평활 패스 수(0=끔). 빠른 국소평균
  EPS_MODE  = 'gate';            % ★ 노이즈 바닥 보정: 'gate'=바닥 미만 증분 0(권장)
                                 %   'sub'=바닥 차감 max(0,dε̄-floor) | 'off'=끔.
                                 %   dε̄는 양수 정의라 강체 이동 중에도 노이즈가
                                 %   매 프레임 +로 정류 누적 → 평행이동 가짜 변형률의 원인
  EPS_K     = 2.0;               % 자동 바닥 = EPS_K × median(dε̄) (강체 영역이 면적
                                 %   대부분 → 중앙값≈노이즈 바닥). 가짜 누적 남으면 ↑(3)
  EPS_FLOOR = [];                % 바닥 고정값(직접 지정 시). 빈 값=매 프레임 자동.
                                 %   ⚠ 화면 대부분이 전단대인 ROI에선 자동 추정이
                                 %     과대 → 고정값 사용 권장
  CMAP      = 'jet';
  CLIM_MAX  = [];                % 컬러바 상한 (빈 값=자동 99%); Image 2처럼은 10 권장
  MAP_ALPHA = 0.85;
  CONTOUR_N = 24;                % contourf 레벨 수(↓=빠름)
  ANIM_PAUSE= 0.02;

  % --- 재료 슬랩(상단 자유표면) 경계 ---
  ASK_MATBND = true;             % 좌측 유입부에서 슬랩 상단→하단 2점 클릭
  MAT_TOP_Y  = [];               % 재료 상단(자유표면) y[px]. 빈 값=클릭/자동
  MAT_BOT_Y  = [];               % 재료 하단 y[px]. 빈 값=프레임 하단(maxY)
  INJECT_X   = [];               % 주입 x[px]. 빈 값=클릭 평균 또는 좌측 유효 끝열

  % --- ★ streakline (마스크 경계 겸 시각화) ---
  %  내부 '마스크선'(비표시)과 화면 '표시선'을 분리:
  %   - 마스크선 N_MASK개: 항상 등분 유지 → 선단 곡선/상하 경계 품질 보장
  %   - 표시선: 사용자가 개수/위치 선택 (SHOW_MODE)
  N_MASK    = 12;                % 마스크용 내부 선 개수(화면 비표시). 선단 각지면 ↑
  SHOW_MODE = 'ndiv';            % 표시선 배치: 'ndiv'=N_SHOW 등분
                                 %              'click'=유입선에서 원하는 y 클릭
                                 %              'list' =SHOW_Y에 y좌표(px) 직접 입력
  N_SHOW    = 5;                 % 'ndiv'일 때 표시선 개수
  SHOW_Y    = [];                % 'list'일 때 y좌표(px) 벡터. 예: [380 420 460]
  STREAK_LW = 2.0;               % 표시선 굵기
  STREAK_SMOOTH = 5;             % ★ 폴리라인 이동평균 창(점 개수, 홀수 권장, 1=끔).
                                 %   표시선과 마스크 경계에 동일 적용(그려진 선=경계).
                                 %   이류용 원본 좌표는 건드리지 않음 → 물리 왜곡 없음
  BND_EXT   = 2;                 % 경계확장 실데이터장 반경(격자 칸).
                                 %   자유표면 위 NaN에 최근접 실측 속도 복사 →
                                 %   맨 위 streak가 표면 밀착. 표면 위로 뜨면 ↓(1),
                                 %   표면 아래서 정체 기미면 ↑(3)
  PATHLINE_SLIDE = true;         % 목적지 NaN 시 각도탐색 슬라이드. false=정지
  NSUB      = 2;                 % ★ 프레임당 이류 서브스텝 수(1=끔). 정체 손실 1/N로 감소,
                                 %   전단대 급회전 곡률 오차 감소. 랙 크면 3~4
  SLIDE_FULLSPEED = true;        % ★ streak 점 슬라이드 시 속도×cosθ 대신 전속 유지.
                                 %   자유표면은 감속 근거 없음 → cos 손실(장기 랙 원인) 제거.
                                 %   strain 입자에는 미적용(공구 접촉 감속은 물리적)
  DIAG_EVERY= 100;               % ★ 이 프레임마다 맨위선 정체/슬라이드율 출력(0=끔).
                                 %   정체율 높음=코드/NaN 문제, 낮은데 랙=PIV 속도 편향
  FILL_GAP  = 3;                 % ★ '재료에 둘러싸인' NaN 채움 반경(격자 칸, 0=끔).
                                 %   imclearborder는 공기와 연결된 칩 가장자리 NaN 만(灣)을
                                 %   못 잡음(정체 주범) → imclose(유효장,FILL_GAP)로 폭
                                 %   ≤2×FILL_GAP 틈까지 채움. 열린 공기는 안 닫힘=가상유동 없음.
                                 %   ⚠ 분절 칩의 실제 공극(inter-segment void)보다 작게 유지
                                 %     — 실공극을 채우면 가짜 유동/가짜 변형률 생성
  SNAP_MAX  = 6;                 % ★ streak 시드 스냅 상한(격자 칸). 클릭한 자유표면이
                                 %   PIV 유효 데이터보다 위(공기)면 시드가 영구 고착
                                 %   (속도 NaN→정체→속도0→슬라이드 불가) → 주입 시점에
                                 %   최근접 유효 셀로 끌어내려 출발 보장. 0=끔
  DEBUG_TOP = false;             % ★ 맨 위 streakline 점을 빨간 마커로 표시(고착/드리프트 진단)

  CONT_INJECT = true;            % 좌측 유입선 연속 주입(strain 입자)
  PRUNE_WALL  = true;            % 깊은 공구 박힌 strain 입자만 제거
  WALL_KEEP   = 2;               % 공구 경계 이 칸수만큼 입자 보존 → 레이크면/툴팁 커버
  WALL_EDGE   = 1;               % vdisp에서 공구를 이 칸수 안으로 깎음 → 모서리까지 색칠
  PRUNE_EXIT  = true;            % 우측 유출(maxX 초과) strain 입자 제거

  DO_MP4    = false;
  MP4_FPS   = 15;
  REC_EVERY = 25;                % ★ 스냅샷 기록 주기(프레임, 0=끔). 마지막 프레임은 항상 기록.
                                 %   기록된 프레임은 종료 후 프롬프트/스크립트로 사후 재렌더 가능
                                 %   (원하는 CLim/컬러맵/프레임 + 600dpi PNG/PDF 추출).
                                 %   메모리: 스냅샷당 입자수×3×4B — 1000프레임/25 = 40장 무난
  ASK_EXTRACT = true;            % ★ 실행 종료 후 추출 대화상자 표시(취소할 때까지 반복):
                                 %   [프레임 / CLim 상한 / 저장 파일명] 입력 → 즉시 재렌더
                                 %   + 파일명 입력 시 600dpi PNG + 벡터 PDF 저장

  %% ===== pivData 로드 =====
  if nargin<1 || isempty(pivData)
    if evalin('base','exist(''pivData'',''var'')'), pivData = evalin('base','pivData');
    else
      [f,p]=uigetfile('*.mat','pivData .mat 선택'); if isequal(f,0), out=[]; return; end
      S=load(fullfile(p,f)); fn=fieldnames(S); pivData=S.(fn{1});
    end
  end
  Nt = size(pivData.U,3);

  %% ===== 프레임 범위 =====
  if isempty(t_start), t_start=1; end
  if isempty(t_end),   t_end=Nt; end
  if ASK_FRAMES
    a=inputdlg({'시작 프레임','끝 프레임'},'프레임 범위',1,{num2str(t_start),num2str(t_end)});
    if ~isempty(a), t_start=str2double(a{1}); t_end=str2double(a{2}); end
  end
  t_start=max(1,min(Nt,round(t_start))); t_end=max(t_start,min(Nt,round(t_end)));
  Nf = t_end - t_start + 1;

  %% ===== 격자/배경 =====
  Xpx=double(pivData.X); Ypx=double(pivData.Y); [ny,nx]=size(Xpx);
  minX=min(Xpx(:)); maxX=max(Xpx(:)); minY=min(Ypx(:)); maxY=max(Ypx(:));
  dx=double(pivData.iaStepX); dy=double(pivData.iaStepY);

  fileList = build_file_list(pivData);
  bg0 = get_bg(fileList,pivData,t_start);
  if isempty(bg0), error('배경 이미지를 찾지 못했습니다.'); end
  if isfield(pivData,'imSizeX'), W=pivData.imSizeX; else, W=size(bg0,2); end
  if isfield(pivData,'imSizeY'), H=pivData.imSizeY; else, H=size(bg0,1); end

  %% ===== 폴백용 '전 프레임 벽' (Status 없을 때) =====
  persistWall = true(ny,nx);
  for k=t_start:t_end
    Uk=double(pivData.U(:,:,k)); Vk=double(pivData.V(:,:,k));
    persistWall = persistWall & (isnan(Uk) | (Uk==0 & Vk==0));
  end
  wall0 = frame_wall(pivData,t_start,persistWall);

  %% ===== strain 입자 간격 =====
  dseed = (maxX-minX)/max(1,round(nx*SEED_REF)-1);   % 대략 입자 간격(px)

  %% ===== 재료 슬랩(상단/하단) 경계 지정 =====
  if ASK_MATBND
    hB=figure('Name','재료 슬랩 경계','Color','w');
    imshow(bg0,'InitialMagnification','fit'); hold on;
    title('재료 슬랩의 상단 → 하단 2점 클릭 (왼쪽 유입부)','FontSize',13);
    [xb,yb]=ginput(2);
    INJECT_X = mean(xb);  MAT_TOP_Y = min(yb);  MAT_BOT_Y = max(yb);
    plot([INJECT_X INJECT_X],[MAT_TOP_Y MAT_BOT_Y],'y-','LineWidth',2);
    plot(INJECT_X,MAT_TOP_Y,'g^','MarkerFaceColor','g','MarkerSize',9);   % 상단=자유표면
    text(INJECT_X+5,MAT_TOP_Y,'  free surface (top streakline)','Color','g','FontWeight','bold');
    pause(0.7); close(hB);
  end
  if isempty(MAT_TOP_Y), MAT_TOP_Y=minY; end
  if isempty(MAT_BOT_Y), MAT_BOT_Y=maxY; end
  if isempty(INJECT_X)
    [~,cc]=find(~wall0); if isempty(cc), INJECT_X=minX; else, INJECT_X=Xpx(1,min(cc)); end
  end
  MAT_TOP_Y=max(min(MAT_TOP_Y,maxY),minY);
  MAT_BOT_Y=max(min(MAT_BOT_Y,maxY),minY);
  INJECT_X =max(min(INJECT_X ,maxX),minX);

  %% ===== 초기 시드 = '유입선만' → 맵이 유입 물질과 함께 좌→우로 자라남 =====
  [Px,Py]=inflow_col(Xpx,Ypx,wall0,INJECT_X,MAT_TOP_Y,MAT_BOT_Y,dseed);
  Eps=zeros(size(Px));

  %% ===== ★ streakline 시드: 마스크선(등분, 비표시) + 표시선(사용자 선택) =====
  syM=linspace(MAT_TOP_Y,MAT_BOT_Y,N_MASK).';          % 마스크선: 1행=맨위 경계, N_MASK행=맨아래
  switch lower(SHOW_MODE)
    case 'click'   % 유입선 근처에서 원하는 위치들 클릭 (Enter로 종료)
      hC=figure('Name','표시 streakline 위치 선택','Color','w');
      imshow(bg0,'InitialMagnification','fit'); hold on;
      plot([INJECT_X INJECT_X],[MAT_TOP_Y MAT_BOT_Y],'y-','LineWidth',2);
      title('표시할 streakline 위치들을 클릭 (y좌표만 사용, Enter로 종료)','FontSize',13);
      [~,ysC]=ginput;
      close(hC);
      syS=sort(ysC(:));
    case 'list'
      syS=sort(SHOW_Y(:));
    otherwise      % 'ndiv'
      syS=linspace(MAT_TOP_Y,MAT_BOT_Y,max(1,N_SHOW)).';
  end
  syS=max(min(syS,MAT_BOT_Y),MAT_TOP_Y);               % 슬랩 범위로 클램프
  sy=[syM; syS];  sx=INJECT_X*ones(size(sy));
  NT=numel(sy);                                        % 전체 추적 선 개수
  idxShow=(N_MASK+1):NT;                               % 화면에 그릴 행 인덱스
  spX=nan(NT,Nf); spY=nan(NT,Nf);   % spX(i,p) = i번 선의 p번째 주입점 현재 위치

  fprintf(['정방향(현재형상): 프레임 %d→%d, 유입선 시드 %d점\n' ...
           '  마스크선 %d개(비표시) + 표시선 %d개(%s), 평활창 %d점\n' ...
           '  유입슬랩 y=[%.1f, %.1f], 주입x=%.1f, 경계=맨 위 마스크선\n'], ...
          t_start,t_end,numel(Px),N_MASK,numel(syS),SHOW_MODE,STREAK_SMOOTH, ...
          MAT_TOP_Y,MAT_BOT_Y,INJECT_X);

  %% ===== 렌더/마스크 격자 =====
  xq=linspace(minX,maxX,max(2,round(nx*DISP_REF)));
  yq=linspace(minY,maxY,max(2,round(ny*DISP_REF)));
  [Xd,Yd]=meshgrid(xq,yq);

  %% ===== ★ 스냅샷 저장소 (사후 추출용) =====
  snap=struct('k',{},'fi',{},'Px',{},'Py',{},'Eps',{},'spX',{},'spY',{});

  %% ===== 그림 + MP4 =====
  hFig=figure('Name','Forward Strain Evolution (top-streakline boundary)','Color','w', ...
              'Position',[80 80 940 580]);
  vidSize=[];
  if DO_MP4
    [vf,vp]=uiputfile('*.mp4','MP4 저장 위치');
    if isequal(vf,0), DO_MP4=false; else
      vw=VideoWriter(fullfile(vp,vf),'MPEG-4'); vw.FrameRate=MP4_FPS; vw.Quality=100; open(vw);
    end
  end
  warning('off','MATLAB:scatteredInterpolant:DupPtsAvValuesWarnId');
  slideAngles = [0, reshape([1;-1]*(5:5:85),1,[])*(pi/180)];   % 슬라이드 각도(0,±5..±85)

  %% ===== 프레임 루프 =====
  for fi=1:Nf
    k=t_start+fi-1;
    Uk=double(pivData.U(:,:,k)); Vk=double(pivData.V(:,:,k));
    wall = frame_wall(pivData,k,persistWall);
    toolw= frame_toolwall(pivData,k,persistWall);       % 공구 전용 벽(공기 제외)

    % --- 프레임당 1회: 공용 속도장 ---
    nanU=isnan(Uk);
    ccHole=imclearborder(nanU);                         % 완전 내부 cc구멍
    % ★ 재료에 '둘러싸인' NaN까지 채움 대상 확장 (칩 가장자리 NaN 만(灣) 대응)
    %   imclearborder는 공기와 연결된 패치를 못 잡음 → 유효장을 FILL_GAP칸
    %   닫아(imclose) 재료에 싸인 좁은 틈만 추가. 열린 공기·공구는 제외.
    if FILL_GAP>0
      encl = imclose(~nanU,strel('disk',FILL_GAP)) & nanU & ~toolw;
      ccHole = ccHole | encl;
    end
    Ufill=inpaint_nans(Uk,4); Vfill=inpaint_nans(Vk,4); % 완전 채움(변형률 미분용)
    Ua=Uk; Va=Vk; Ua(ccHole)=Ufill(ccHole); Va(ccHole)=Vfill(ccHole);  % 실데이터장
    % ★ 경계확장 실데이터장: 유효 셀 BND_EXT칸 이내 NaN에 최근접 실측값 복사
    validA=~isnan(Ua);
    Uex=Ua; Vex=Va;
    if any(validA(:))                                   % 전체 NaN 프레임 방어
      [distA,idxA]=bwdist(validA);
      extA=~validA & (distA<=BND_EXT);
      Uex(extA)=Ua(idxA(extA)); Vex(extA)=Va(idxA(extA));
    end
    Uex(toolw)=NaN; Vex(toolw)=NaN;                     % 공구로는 확장 금지(관통 방지)
    % ★ 확장장 기준 유효맵 + 최근접 유효 셀 인덱스 (시드 스냅용)
    validEx=~isnan(Uex);
    if any(validEx(:)), [~,idxE]=bwdist(validEx); else, idxE=[]; end

    % --- 좌측 연속 주입 (strain 입자, 신선 입자 누적 0) ---
    if CONT_INJECT && fi>=2
      [ix,iy]=inflow_col(Xpx,Ypx,wall,INJECT_X,MAT_TOP_Y,MAT_BOT_Y,dseed);
      Px=[Px;ix]; Py=[Py;iy]; Eps=[Eps;zeros(numel(ix),1)];
    end

    % --- 증분 유효변형률 dε̄ (벽 NaN, NaN-aware 편측차분) ---
    dEbar = incr_eff_strain(Ufill,Vfill,dx,dy,SMOOTH_VEL,wall);

    % --- ★ 노이즈 바닥 보정: 강체 이동 중 가짜 변형률 정류 누적 차단 ---
    %   dε̄=√(제곱합)≥0 → 노이즈 구배가 매 프레임 양의 증분으로 정류됨.
    %   화면 대부분이 강체(시편/칩 벌크)라 median(dε̄)≈노이즈 바닥.
    epsFloor=0;
    if ~strcmpi(EPS_MODE,'off')
      if isempty(EPS_FLOOR)
        vv0=dEbar(~isnan(dEbar));
        if ~isempty(vv0), epsFloor=EPS_K*median(vv0); end
      else
        epsFloor=EPS_FLOOR;
      end
      switch lower(EPS_MODE)
        case 'sub',  dEbar=max(0,dEbar-epsFloor);      % 바닥 차감(전단대도 소폭 감소)
        otherwise,   dEbar(dEbar<epsFloor)=0;          % 'gate': 바닥 미만 0(전단대 보존)
      end
    end

    % --- 누적: 입자의 '현재 위치'에서 샘플 ---
    dEp=interp2(Xpx,Ypx,dEbar,Px,Py,'linear',NaN);
    add=~isnan(dEp); Eps(add)=Eps(add)+dEp(add);

    % --- ★ streakline 현재 주입점 등록 (매 프레임 유입선에서 새 점 1개/선) ---
    %   시드가 유효 속도장 밖(공기)이면 최근접 유효 셀로 스냅 → 고착 방지.
    %   맨 위 시드가 PIV 데이터 최상단 행에 붙어 출발 → 맨 위 streakline이
    %   실측 가능한 최상단 재료 표면을 따라감(= 색칠 경계)
    if SNAP_MAX>0 && ~isempty(idxE)
      [sxx,syy,nsnap]=snap_to_valid(sx,sy,validEx,idxE,Xpx,Ypx,SNAP_MAX);
      if fi==1 && nsnap>0
        fprintf('  [snap] 유효장 밖 streak 시드 %d개를 최근접 유효 셀로 이동\n',nsnap);
      end
    else
      sxx=sx; syy=sy;
    end
    spX(:,fi)=sxx; spY(:,fi)=syy;

    % --- ★ 스냅샷 기록 (렌더 직전 상태 = 프레임 fi의 완전한 상태) ---
    %   out.snap에 저장되어 사후 재렌더/내보내기에 사용 (이 파일 하단의 extract_render 로컬 함수 참조)
    if REC_EVERY>0 && (mod(fi,REC_EVERY)==0 || fi==Nf)
      snap(end+1)=struct('k',k,'fi',fi, ...
        'Px',single(Px),'Py',single(Py),'Eps',single(Eps), ...
        'spX',single(spX(:,1:fi)),'spY',single(spY(:,1:fi))); %#ok<AGROW>
    end

    % --- 렌더 ---
    clf(hFig); ax=axes('Parent',hFig);
    bg=get_bg(fileList,pivData,k);
    image(ax,[1 W],[1 H],bg); set(ax,'YDir','reverse'); hold(ax,'on');

    % 유입 초기: 입자가 적거나 공선 → 삼각분할 불가 → 그 프레임 색 생략
    field=nan(size(Xd));
    canInterp = numel(Px)>=3 && (max(Px)-min(Px))>0.5*dseed && (max(Py)-min(Py))>0.5*dseed;
    if canInterp
      try
        F=scatteredInterpolant(Px,Py,Eps,'linear','nearest');% 폴리곤 안 빈틈 없이 채움
        tmp=F(Xd,Yd);
        if isequal(size(tmp),size(Xd)), field=tmp; end       % 퇴화 시 빈/스칼라 반환 방어
      catch
        field=nan(size(Xd));
      end
    end

    % ★ 렌더용 평활 폴리라인 (이류용 원본 spX/spY는 불변 — 물리 왜곡 없음)
    spXr=spX; spYr=spY;
    if STREAK_SMOOTH>1
      for i=1:NT
        [spXr(i,1:fi),spYr(i,1:fi)]=smooth_poly(spX(i,1:fi),spY(i,1:fi),STREAK_SMOOTH);
      end
    end

    % ★ 색칠 마스크 = 맨 위(1)~맨 아래(N_MASK) '마스크선' 폴리곤 안쪽 (평활 좌표)
    inMat = streakline_mask(spXr(1:N_MASK,:),spYr(1:N_MASK,:),1,N_MASK,fi,xq,yq);
    field(~inMat)=NaN;
    % 공구(벽) 제거 — 모서리까지 색칠 위해 공구를 WALL_EDGE칸 깎음
    if WALL_EDGE>0, wallV=imerode(wall,strel('disk',WALL_EDGE)); else, wallV=wall; end
    vdisp=interp2(Xpx,Ypx,double(~wallV),Xd,Yd,'nearest',0)>0.5;
    field(~vdisp)=NaN;

    % 유효한 2D 필드 + 값이 하나라도 있을 때만 색칠(초기 빈 프레임 방어)
    if isequal(size(field),size(Xd)) && any(~isnan(field(:)))
      [~,hc]=contourf(ax,Xd,Yd,field,CONTOUR_N,'LineStyle','none');
      try, alpha(hc,MAP_ALPHA); catch, end
    end

    % ★ 표시선만 그림(검정, 평활 좌표) — 마스크선은 비표시
    for i=idxShow, plot(ax,spXr(i,1:fi),spYr(i,1:fi),'k-','LineWidth',STREAK_LW); end
    if DEBUG_TOP   % 맨 위 마스크선 점(원본)을 마커로: 시드에 뭉침=고착 / 궤적 분포=정상
      plot(ax,spX(1,1:fi),spY(1,1:fi),'r.','MarkerSize',10);
    end

    colormap(ax,CMAP);
    if ~isempty(CLIM_MAX), set(ax,'CLim',[0 CLIM_MAX]);
    else, vv=field(~isnan(field)); if ~isempty(vv), set(ax,'CLim',[0 max(pctl99(vv),eps)]); end
    end
    cb=colorbar(ax); ylabel(cb,'$\bar{\epsilon}$ (effective strain)','Interpreter','latex');
    axis(ax,'image'); axis(ax,[1 W 1 H]);
    title(ax,sprintf('Forward 누적 변형률 (맨위 streakline 경계)   Frame %d / %d   (입자 %d)', ...
          k,t_end,numel(Px)),'FontSize',13);
    drawnow;

    if DO_MP4
      fr=print(hFig,'-RGBImage','-r120');
      if isempty(vidSize), vidSize=[size(fr,1) size(fr,2)]; end
      if size(fr,1)~=vidSize(1)||size(fr,2)~=vidSize(2), fr=imresize(fr,vidSize); end
      writeVideo(vw,fr);
    end
    pause(ANIM_PAUSE);

    if fi==Nf, break; end

    % --- 이류 ①: strain 입자 (경계확장 실데이터장 + 슬라이드 + 서브스텝) ---
    [Pxn,Pyn]=advect_sub(Px,Py,Uex,Vex,Xpx,Ypx,slideAngles,PATHLINE_SLIDE,false,NSUB);

    % --- 우측 유출 입자 prune ---
    if PRUNE_EXIT
      ex=Pxn>maxX; Pxn(ex)=[]; Pyn(ex)=[]; Eps(ex)=[];
    end
    Px=max(min(Pxn,maxX),minX); Py=max(min(Pyn,maxY),minY);

    % --- (안전망) 깊은 공구 박힌 입자 prune ---
    if PRUNE_WALL
      wnext = frame_wall(pivData,k+1,persistWall);
      if WALL_KEEP>0, wdeep=imerode(wnext,strel('disk',WALL_KEEP)); else, wdeep=wnext; end
      inw = interp2(Xpx,Ypx,double(wdeep),Px,Py,'nearest',0) > 0.5;
      Px(inw)=[]; Py(inw)=[]; Eps(inw)=[];
    end

    % --- 이류 ②: ★ 모든 streak 점(마스크선+표시선) — 서브스텝 + 전속 슬라이드 ---
    %   맨 위 마스크선도 NaN을 만나면 각도탐색으로 미끄러지며 전진(고착 X).
    %   prune 없이 클램프만 → spX/spY 행렬 정렬 유지(선이 끊기지 않음)
    xc=spX(:,1:fi); yc=spY(:,1:fi);
    [xn,yn,lostF,slideF]=advect_sub(xc(:),yc(:),Uex,Vex,Xpx,Ypx, ...
                                    slideAngles,PATHLINE_SLIDE,SLIDE_FULLSPEED,NSUB);
    xn=reshape(xn,NT,fi); yn=reshape(yn,NT,fi);
    spX(:,1:fi)=max(min(xn,maxX),minX);
    spY(:,1:fi)=max(min(yn,maxY),minY);
    % ★ 랙 진단: 맨 위 마스크선의 정체/슬라이드 서브스텝 비율
    %   정체율 높음 → NaN/확장 부족(코드로 개선: BND_EXT↑, NSUB↑)
    %   정체율 낮은데 랙 → PIV 속도 과소평가(데이터 한계, 코드로 못 고침)
    if DIAG_EVERY>0 && mod(fi,DIAG_EVERY)==0
      lostF=reshape(lostF,NT,fi); slideF=reshape(slideF,NT,fi);
      fprintf('  [diag] f%d: 맨위선 정체 %.1f%% / 슬라이드 %.1f%% | 노이즈바닥 dε̄=%.4g/frame\n', ...
              k,100*mean(lostF(1,:)),100*mean(slideF(1,:)),epsFloor);
    end
  end
  if DO_MP4, close(vw); fprintf('MP4 저장 완료\n'); end

  out.Px=Px; out.Py=Py; out.Eps=Eps; out.frames=[t_start t_end];
  out.matTopY=MAT_TOP_Y; out.matBotY=MAT_BOT_Y; out.injectX=INJECT_X;
  out.streakX=spX; out.streakY=spY;
  out.nMask=N_MASK; out.idxShow=idxShow;               % 1..N_MASK=마스크선, idxShow=표시선
  out.snap=snap; out.snapFrames=[snap.k];              % ★ 추출 가능한 프레임 목록
  out.xq=xq; out.yq=yq;                                % 렌더 격자(추출 시 동일 격자 사용)
  out.cfg=struct('N_MASK',N_MASK,'idxShow',idxShow, ...% ★ 추출용 렌더 설정 일체
    'STREAK_SMOOTH',STREAK_SMOOTH,'STREAK_LW',STREAK_LW, ...
    'WALL_EDGE',WALL_EDGE,'CMAP',CMAP,'MAP_ALPHA',MAP_ALPHA, ...
    'CONTOUR_N',CONTOUR_N,'CLIM_MAX',CLIM_MAX,'tRange',[t_start t_end]);
  out.config='current(forward,top-streakline-boundary,slide,edge-extended-realdata,snap,smooth)';
  disp('>> 정방향 시간진화 변형률 맵(맨위 streakline 경계) 완료.');
  fprintf('   스냅샷 %d장 기록: out.snapFrames 확인\n',numel(snap));

  %% ===== ★ 종료 후 추출 프롬프트 (취소할 때까지 반복) =====
  %  기록된 스냅샷 중 원하는 프레임을 원하는 변형률 바 범위로 즉시 재렌더.
  %  저장 파일명 입력 시 600dpi PNG + 벡터 PDF(Arial) 저장.
  if ASK_EXTRACT && ~isempty(snap)
    kList=[snap.k];
    while true
      a=inputdlg({sprintf('추출 프레임 (기록 %d장: %d ~ %d, 가장 가까운 것 선택)', ...
                          numel(kList),kList(1),kList(end)), ...
                  '변형률 바 상한 CLim max (빈 칸=자동 99%)', ...
                  '저장 파일명 (빈 칸=저장 안 함, 예: fig_f500)'}, ...
                 '스냅샷 추출 — 취소 누르면 종료',1, ...
                 {num2str(kList(end)),'',''});
      if isempty(a), break; end                        % 취소 → 종료
      fReq=str2double(a{1}); climMax=str2double(a{2}); expName=strtrim(a{3});
      if isnan(fReq), continue; end
      [~,j]=min(abs(kList-fReq));
      if kList(j)~=fReq
        fprintf('  요청 %d → 가장 가까운 기록 프레임 %d 사용\n',fReq,kList(j));
      end
      extract_render(snap(j),pivData,fileList,Xpx,Ypx,xq,yq,persistWall, ...
                     N_MASK,idxShow,STREAK_SMOOTH,STREAK_LW,WALL_EDGE, ...
                     CMAP,MAP_ALPHA,CONTOUR_N,climMax,expName);
    end
  end
end

%% ============================================================
%% 로컬: ★ 스냅샷 재렌더 (종료 후 추출 프롬프트에서 호출)
%%   본체와 동일한 마스크/평활/공구제거 로직으로 지정 프레임을 다시 그림.
%%   climMax: NaN=자동 99%. expName 비어있지 않으면 PNG(600dpi)+PDF 저장.
%%   논문 스타일: Arial, 바깥 틱.
%% ============================================================
function extract_render(S,pivData,fileList,Xpx,Ypx,xq,yq,persistWall, ...
                        N_MASK,idxShow,STREAK_SMOOTH,STREAK_LW,WALL_EDGE, ...
                        CMAP,MAP_ALPHA,CONTOUR_N,climMax,expName)
  k=S.k; fi=S.fi;
  [Xd,Yd]=meshgrid(xq,yq);
  wall=frame_wall(pivData,k,persistWall);
  if WALL_EDGE>0, wallV=imerode(wall,strel('disk',WALL_EDGE)); else, wallV=wall; end
  vdisp=interp2(Xpx,Ypx,double(~wallV),Xd,Yd,'nearest',0)>0.5;
  Px=double(S.Px); Py=double(S.Py); Eps=double(S.Eps);
  field=nan(size(Xd));
  if numel(Px)>=3
    try
      F=scatteredInterpolant(Px,Py,Eps,'linear','nearest');
      tmp=F(Xd,Yd); if isequal(size(tmp),size(Xd)), field=tmp; end
    catch, end
  end
  spX=double(S.spX); spY=double(S.spY); NT=size(spX,1);
  if STREAK_SMOOTH>1 && fi>=3
    for i=1:NT
      [spX(i,:),spY(i,:)]=smooth_poly(spX(i,:),spY(i,:),STREAK_SMOOTH);
    end
  end
  inMat=streakline_mask(spX(1:N_MASK,:),spY(1:N_MASK,:),1,N_MASK,fi,xq,yq);
  field(~inMat)=NaN; field(~vdisp)=NaN;
  bg=get_bg(fileList,pivData,k);
  if isempty(bg), warning('배경 이미지 없음 — 추출 중단'); return; end
  if isfield(pivData,'imSizeX'), W=pivData.imSizeX; else, W=size(bg,2); end
  if isfield(pivData,'imSizeY'), H=pivData.imSizeY; else, H=size(bg,1); end
  hF=figure('Name',sprintf('Extract — frame %d',k),'Color','w','Position',[120 120 940 580]);
  ax=axes('Parent',hF);
  image(ax,[1 W],[1 H],bg); set(ax,'YDir','reverse'); hold(ax,'on');
  if any(~isnan(field(:)))
    [~,hc]=contourf(ax,Xd,Yd,field,CONTOUR_N,'LineStyle','none');
    try, alpha(hc,MAP_ALPHA); catch, end
  end
  for i=idxShow, plot(ax,spX(i,:),spY(i,:),'k-','LineWidth',STREAK_LW); end
  colormap(ax,CMAP);
  if ~isnan(climMax) && climMax>0
    set(ax,'CLim',[0 climMax]);
  else
    vv=field(~isnan(field));
    if ~isempty(vv), set(ax,'CLim',[0 max(pctl99(vv),eps)]); end
  end
  cb=colorbar(ax); ylabel(cb,'$\bar{\epsilon}$ (effective strain)','Interpreter','latex');
  axis(ax,'image'); axis(ax,[1 W 1 H]);
  set(ax,'FontName','Arial','TickDir','out');
  set(cb,'FontName','Arial','TickDirection','out');
  title(ax,sprintf('Cumulative effective strain — frame %d',k), ...
        'FontName','Arial','FontSize',13);
  drawnow;
  if ~isempty(expName)
    exportgraphics(hF,[expName '.png'],'Resolution',600);
    exportgraphics(hF,[expName '.pdf'],'ContentType','vector');
    fprintf('저장: %s.png (600dpi), %s.pdf (vector)\n',expName,expName);
  end
end

%% ============================================================
%% 로컬: ★ 폴리라인 평활 (렌더/마스크 전용, 이류 좌표 불변)
%%   이동평균(movmean) 창 w. 시드(끝)와 선단(시작) 점은 고정해
%%   경계가 유입선/선단에서 밀리지 않게 함.
%% ============================================================
function [xs,ys]=smooth_poly(x,y,w)
  if w<=1 || numel(x)<3, xs=x; ys=y; return; end
  xs=movmean(x,w); ys=movmean(y,w);
  xs(1)=x(1); ys(1)=y(1);          % 최고참 점(선단) 고정
  xs(end)=x(end); ys(end)=y(end);  % 최신 주입점(시드) 고정
end

%% ============================================================
%% 로컬: ★ 유효장 스냅 — 점이 유효 속도장(validEx) 밖 셀에 있으면
%%   bwdist 최근접 유효 셀 좌표로 이동(상한 maxCells 칸).
%%   목적: 클릭 시드가 PIV 데이터 위 공기에 있을 때의 '영구 고착'
%%   (속도 NaN→정체→속도0→슬라이드 실패) 차단. 이동 거리 상한으로
%%   엉뚱한 곳(멀리 떨어진 칩 등)으로 튀는 것 방지.
%% ============================================================
function [px,py,nsnap]=snap_to_valid(px,py,validEx,idxE,Xpx,Ypx,maxCells)
  [nyg,nxg]=size(validEx);
  x0=Xpx(1,1); y0=Ypx(1,1);
  stx=(Xpx(1,end)-x0)/max(1,nxg-1);   % 격자 간격(px)
  sty=(Ypx(end,1)-y0)/max(1,nyg-1);
  ci=round((px-x0)/stx)+1; ri=round((py-y0)/sty)+1;   % 점 → 격자 셀 인덱스
  ci=max(1,min(nxg,ci)); ri=max(1,min(nyg,ri));
  lin=sub2ind([nyg,nxg],ri,ci);
  bad=~validEx(lin);                                   % 유효장 밖 점
  nsnap=0;
  if any(bad)
    tgt=double(idxE(lin(bad)));                        % 최근접 유효 셀(선형 인덱스)
    [tr,tc]=ind2sub([nyg,nxg],tgt);
    dcell=hypot(tr-ri(bad),tc-ci(bad));                % 셀 단위 거리
    mv=dcell<=maxCells;                                % 상한 이내만 이동
    bidx=find(bad); bidx=bidx(mv); tgt=tgt(mv);
    px(bidx)=Xpx(tgt); py(bidx)=Ypx(tgt);
    nsnap=numel(bidx);
  end
end

%% ============================================================
%% 로컬: ★ 실데이터 이류 (strain 입자 & streak 점 공용)
%%   - linear 실패(경계셀) → nearest 재시도, 정체(0/NaN) → 제자리
%%   - 목적지 NaN(공기/공구) → 벡터화 각도탐색 슬라이드(0,±5..±85°) or 정지
%%   - fullSpeed=true: 슬라이드 시 속도×cosθ 대신 전속(자유표면용, cos 랙 제거)
%%   - stallM: 이번 호출에서 못 움직인 점(랙 진단용), slideM: 슬라이드한 점
%% ============================================================
function [Pxn,Pyn,stallM,slideM]=advect_real(Px,Py,Ua,Va,Xpx,Ypx,slideAngles,useSlide,fullSpeed)
  if nargin<9, fullSpeed=false; end
  up=interp2(Xpx,Ypx,Ua,Px,Py,'linear'); vp=interp2(Xpx,Ypx,Va,Px,Py,'linear');
  bad=isnan(up)|isnan(vp);                            % 경계셀: nearest 재시도
  if any(bad)
    up(bad)=interp2(Xpx,Ypx,Ua,Px(bad),Py(bad),'nearest');
    vp(bad)=interp2(Xpx,Ypx,Va,Px(bad),Py(bad),'nearest');
  end
  stag=isnan(up)|isnan(vp)|(up==0 & vp==0); up(stag)=0; vp(stag)=0;   % 정체 → 제자리
  Pxn=Px+up; Pyn=Py+vp;
  slideM=false(size(Px));

  % 경계(공기/공구) 진입: 각도탐색 슬라이드 또는 정지
  destNaN=isnan(interp2(Xpx,Ypx,Ua,Pxn,Pyn,'nearest'));
  if useSlide && any(destNaN)
    bidx=find(destNaN);
    a0 =atan2(vp(bidx),up(bidx));  spB=hypot(up(bidx),vp(bidx));     % B×1
    AT =a0+slideAngles;                                              % B×A (암시적 확장)
    if fullSpeed, SPJ=spB.*ones(size(slideAngles));                  % 전속 유지(자유표면)
    else,         SPJ=spB.*cos(slideAngles);                         % 접선 성분(벽 접촉)
    end
    XT =Px(bidx)+cos(AT).*SPJ;  YT=Py(bidx)+sin(AT).*SPJ;            % B×A
    VAL=interp2(Xpx,Ypx,Ua,XT,YT,'nearest');                         % 단 1회 벡터화 호출
    okM=~isnan(VAL);  okM(spB<=0,:)=false;
    [hasV,jA]=max(okM,[],2);  mv=hasV>0;
    if any(mv)
      li=sub2ind(size(XT),find(mv),jA(mv));
      Pxn(bidx(mv))=XT(li);  Pyn(bidx(mv))=YT(li);                   % 미끄러진 위치
      slideM(bidx(mv))=true;
    end
    Pxn(bidx(~mv))=Px(bidx(~mv)); Pyn(bidx(~mv))=Py(bidx(~mv));      % 실패→제자리
  elseif any(destNaN)
    Pxn(destNaN)=Px(destNaN); Pyn(destNaN)=Py(destNaN);              % 정지
  end
  stallM=(Pxn==Px)&(Pyn==Py);   % 이번 호출에서 이동 0 = 변위 손실(누적되면 랙)
end

%% ============================================================
%% 로컬: ★ 서브스텝 이류 래퍼 — 속도/NSUB로 NSUB회 반복
%%   효과: (1) 정체 1회 손실이 프레임 변위의 1/NSUB로 축소
%%         (2) 급회전 구간(전단대)의 1차 오일러 곡률 오차 감소
%%   lostFrac/slideFrac: 점별 정체/슬라이드 서브스텝 비율(진단용)
%% ============================================================
function [Px,Py,lostFrac,slideFrac]=advect_sub(Px,Py,U,V,Xpx,Ypx,slideAngles,useSlide,fullSpeed,nsub)
  nsub=max(1,round(nsub));
  Us=U/nsub; Vs=V/nsub;
  lost=zeros(size(Px)); slid=zeros(size(Px));
  for s=1:nsub
    [Px,Py,stallM,slideM]=advect_real(Px,Py,Us,Vs,Xpx,Ypx,slideAngles,useSlide,fullSpeed);
    lost=lost+stallM; slid=slid+slideM;
  end
  lostFrac=lost/nsub; slideFrac=slid/nsub;
end

%% ============================================================
%% 로컬: ★ streakline 마스크 = '인접 선 스트립 합집합' (자기교차 내성)
%%   [구버전 문제] 전체를 한 폴리곤([맨위선]+[선단]+[맨아래선])으로 만들면
%%   poly2mask의 even-odd 규칙 때문에 (a) 맨위선의 국소 접힘,
%%   (b) 맨위선 선단이 내부 선 선단보다 뒤처질 때의 선단 교차 →
%%   칩 상단 영역이 구멍/폴리곤 밖으로 뒤집혀 '있다가 사라지는' 깜빡임 발생.
%%   [신버전] 인접 마스크선 쌍(i,i+1)마다 스트립 폴리곤
%%     [i선: p=fi→1] + [i+1선: p=1→fi] (+ 시드측/선단측 자동 닫힘)
%%   을 만들고 합집합(OR). 인접 선은 거의 평행 → 전역 자기교차 없음,
%%   선단 뒤처짐은 스트립 끝 변이 덮음. 잔여 미세 접힘 구멍은 imfill 정리.
%%   ⚠ imfill은 칩이 완전히 말려 '진짜 공기'를 감싸는 극단 케이스도 채움
%%     (현 데이터 해당 없음. 강한 컬링 데이터에선 이 줄 재검토)
%% ============================================================
function inMat = streakline_mask(spX,spY,iTop,iBot,fi,xq,yq)
  nxq=numel(xq); nyq=numel(yq);
  inMat=false(nyq,nxq);
  drx=(xq(end)-xq(1))/max(1,nxq-1); dry=(yq(end)-yq(1))/max(1,nyq-1);
  for i=iTop:iBot-1
    pX=[spX(i,fi:-1:1), spX(i+1,1:fi)];
    pY=[spY(i,fi:-1:1), spY(i+1,1:fi)];
    ok=~isnan(pX)&~isnan(pY); pX=pX(ok); pY=pY(ok);
    if numel(pX)<3, continue; end                     % 초기(점 부족) 스트립 생략
    ci=(pX - xq(1))/drx + 1;   % px → 렌더격자 열 인덱스
    ri=(pY - yq(1))/dry + 1;   % px → 렌더격자 행 인덱스
    inMat = inMat | poly2mask(ci, ri, nyq, nxq);      % 스트립 합집합
  end
  if any(inMat(:)), inMat=imfill(inMat,'holes'); end  % 접힘 잔여 구멍 제거
end

%% ============================================================
%% 로컬: 프레임 벽 마스크 (Status bit1 ∪ persistWall) — 변형률/표시용
%% ============================================================
function wm = frame_wall(pivData,k,persistWall)
  wm = persistWall;
  if isfield(pivData,'Status') && ~isempty(pivData.Status)
    St=pivData.Status; if ndims(St)>=3, Sk=St(:,:,min(k,size(St,3))); else, Sk=St; end
    try, wm = wm | (bitget(uint16(Sk),1) > 0); catch, end
  end
end

%% ============================================================
%% 로컬: '공구 전용' 벽 마스크 (Uex 확장 금지 영역)
%%   frame_wall과 달리 persistWall(공기 포함)을 합치지 않음.
%%   - Status 있으면: bit1(마스킹=공구)만 → 공기는 벽 아님
%%   - Status 없으면: 구분 불가 → persistWall 폴백
%% ============================================================
function wm = frame_toolwall(pivData,k,persistWall)
  if isfield(pivData,'Status') && ~isempty(pivData.Status)
    St=pivData.Status; if ndims(St)>=3, Sk=St(:,:,min(k,size(St,3))); else, Sk=St; end
    try
      wm = bitget(uint16(Sk),1) > 0;
      return;
    catch
    end
  end
  wm = persistWall;   % Status 없음 → 폴백
end

%% ============================================================
%% 로컬: 좌측 유입선 신선 입자 (슬랩 상단경계 아래 & 벽 아닌 y만)
%% ============================================================
function [ix,iy]=inflow_col(Xpx,Ypx,wall,xInject,yTop,yBot,dseed)
  yv=(yTop:dseed:yBot).';
  if numel(yv)<2, yv=[yTop;yBot]; end
  xv=xInject*ones(size(yv));
  ok=interp2(Xpx,Ypx,double(~wall),xv,yv,'nearest',0) > 0.5;
  ix=xv(ok); iy=yv(ok);
end

%% ============================================================
%% 로컬: 증분 유효변형률 (cc실패 채움 + 벽 NaN + NaN-aware 편측차분)
%% ============================================================
function dE = incr_eff_strain(Ufill,Vfill,dx,dy,nSmooth,wall)
  Uf=smooth_wall(Ufill,wall,nSmooth);
  Vf=smooth_wall(Vfill,wall,nSmooth);
  [dUx,dUy]=nan_grad(Uf,dx,dy);          % 벽(NaN) 경계는 편측차분
  [dVx,dVy]=nan_grad(Vf,dx,dy);
  exy=0.5*(dUy+dVx);
  dE=sqrt((2/3)*(dUx.^2 + dVy.^2 + 2*exy.^2));   % dε̄ (항상 ≥ 0)
end

function Ff=smooth_wall(F,wall,nSmooth)
  Ff=F;                          % 이미 채워진 입력(NaN 없음)
  for s=1:nSmooth, Ff=lightsmooth(Ff); end
  Ff(wall)=NaN;                  % 벽만 NaN 복원 (cc실패는 채워진 채로)
end

%% ============================================================
%% 로컬: 빠른 평균 평활(NaN 없는 채운 장 전용)
%% ============================================================
function Fs = lightsmooth(F)
  k=[1 2 1;2 4 2;1 2 1]/16;
  Fs=conv2(F,k,'same');
  Fs([1 end],:)=F([1 end],:); Fs(:,[1 end])=F(:,[1 end]);   % 가장자리는 원본 유지
end

%% ============================================================
%% 로컬: 벡터화 NaN-aware 구배 (벽 경계 편측차분)
%% ============================================================
function [dFdx,dFdy]=nan_grad(F,dx,dy)
  [ny,nx]=size(F);
  dFdx=nan(ny,nx); dFdy=nan(ny,nx);
  vF=~isnan(F);
  % x방향(열)
  L=[nan(ny,1), F(:,1:end-1)];  R=[F(:,2:end), nan(ny,1)];
  vL=~isnan(L); vR=~isnan(R);
  c=vF&vL&vR; dFdx(c)=(R(c)-L(c))/(2*dx);
  f=vF&~vL&vR; dFdx(f)=(R(f)-F(f))/dx;
  b=vF&vL&~vR; dFdx(b)=(F(b)-L(b))/dx;
  % y방향(행)
  Uu=[nan(1,nx); F(1:end-1,:)];  Dd=[F(2:end,:); nan(1,nx)];
  vU=~isnan(Uu); vD=~isnan(Dd);
  c=vF&vU&vD; dFdy(c)=(Dd(c)-Uu(c))/(2*dy);
  f=vF&~vU&vD; dFdy(f)=(Dd(f)-F(f))/dy;
  b=vF&vU&~vD; dFdy(b)=(F(b)-Uu(b))/dy;
end

%% ============================================================
%% 로컬: 배경 fileList / 단일 프레임 배경 / 99퍼센타일
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