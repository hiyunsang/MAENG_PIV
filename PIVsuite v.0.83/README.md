# MAENG PIV — 절삭가공 PIV 분석 파이프라인

PIVsuite v0.83 엔진 기반의 직교절삭(orthogonal cutting) PIV 분석 · 후처리 코드 모음.

## 실행 스크립트 (루트)

| 스크립트 | 용도 |
|---|---|
| `MAENG_PAIR.m` | 선택한 두 프레임(페어) PIV 분석 — 폴더·마스크·frameA/B 지정 후 F5 |
| `MAENG_SEQ.m` | 이미지 시퀀스 전체 PIV 분석 (저장/재로드, SNR 품질 Figure, 절삭속도 검증 포함) |
| `MAENG_SEQ_MULTICORE.m` | MAENG_SEQ와 동일 계산을 여러 MATLAB 워커로 병렬 수행 |

실행 스크립트가 시작될 때 `core/`, `postprocess/` 경로를 자동 등록합니다.
후처리 함수만 따로 쓰려면 먼저 아무 실행 스크립트나 한 번 돌리거나 두 폴더를 addpath 하세요.

## core/ — PIVsuite 엔진 (수정하지 않음)

상호상관 계산 엔진과 서드파티 유틸(smoothn, inpaint_nans 등).
`pivParams`(설정), `pivAnalyzeImagePair/Sequence`(분석), `pivQuiver`(시각화)가 핵심 진입점.

## postprocess/ — MAENG 후처리 도구

분석이 끝난 `pivData`를 입력으로 사용 (대부분 워크스페이스에서 자동 로드, F5 실행 지원).

| 함수 | 용도 |
|---|---|
| `MAENG_EffStrain` | 두 프레임의 순간 유효 변형률 비교 (jet 오버레이) |
| `MAENG_StrainmapFwd` / `Bwd` | 전방/후방 pathline 누적 변형률 맵 + streakline |
| `MAENG_Pathlines` | 입자 경로선(pathline) 추적 + MP4 저장 |
| `MAENG_GridPathlineRotated` | 회전 그리드 추적 (연속 유입 재료선 시각화) |
| `MAENG_Streaklines` | 연속 주입 유맥선 생성 |
| `MAENG_SSZExtract` / `SSZBandExtract` / `SSZShapeTime` | 2차전단영역(SSZ) 추출·두께·시간 적층 |
| `MAENG_FindStagnationPoint` | 프레임별 정체점 탐지 |
| `MAENG_CuttingSpeedAnalyze` | ROI 기반 절삭속도 통계 검증 |
| `MAENG_VelocityDistrib` | 라인 프로파일 속도·전단률 분포 |
| `MAENG_VelocityVideo` | 속도장 MP4 영상 출력 |
| `MAENG_VisualizePairFromSequence` | 시퀀스 결과에서 단일 페어/시간평균 시각화 |
| `MAENG_QualityFigure` | 논문용 ccPeak/SNR 품질 Figure |

## 일반적인 워크플로

1. `MAENG_SEQ.m`(또는 `MAENG_PAIR.m`)에서 이미지 폴더·마스크 경로 지정 → F5
2. 분석 완료 후 워크스페이스의 `pivData`를 가지고 후처리 실행
   (예: `MAENG_EffStrain` F5 → 프레임 두 개 입력 → 변형률 비교 그림)
