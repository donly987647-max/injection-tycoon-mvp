# VFX P0 — 정보용 피드백 (온보딩 게이트)

**범위:** 사출 성공 / 불량 / 과열 / 납품만. 파티클 0, 셰이더 0. ColorRect/`modulate`/1-frame TextureRect.
**스타일:** ART_BIBLE — 클린 카툰, 정보 > 화려함.

## 공유 규칙
- 지속: **180–220ms** (과열 경고만 펄스 2회)
- 색만으로 구분 금지 → **아이콘/핍 + 색**
- Z: 팩토리 위, HUD 아래
- 에셋: `res://assets/art/factory/good_pip.svg`, `defect_pip.svg` (기존)

## 1. 사출 성공 (샷 양품)
| | |
|---|---|
| Trigger | 사이클 사출 후 good unit 증가 |
| Where | MoldBlock 중심 |
| Look | 흰 플래시 1프레임 → `good_pip` 64px 떠오름(−24px) + fade |
| Color | paper `#F4F1EA` flash / ok `#5DD4A0` pip |
| Audio (P1) | soft tick |

## 2. 불량 (NG)
| | |
|---|---|
| Trigger | defect unit 발생 |
| Where | OutputBin 상단 |
| Look | `defect_pip` 팝 + 살짝 shake(±3px, 2회) |
| Color | defect `#E25B4A` |
| Audio (P1) | muted down-blip |

## 3. 과열
| | |
|---|---|
| Trigger | heat ≥ max_heat 또는 COOLING 진입 |
| Where | Machine 전체 |
| Look | Machine `modulate` → `machine_cool` `#C45C5C` 펄스 2회(150ms) + heat bar danger |
| No | 불꽃/연기 파티클 |
| Audio (P1) | warning buzz once |

## 4. 납품 / 정산
| | |
|---|---|
| Trigger | deliver settle |
| Success | HUD 잔고 punch scale 1→1.12→1 (200ms) + sheet ok 틴트 `#5DD4A0` |
| Fail | toast 배경 `#E25B4A` + Machine 짧게 dim |
| Audio (P1) | cash / dry thud |

## Programmer 계약
- Unique 노드: `Machine`, `MoldBlock`, `OutputBin`, HUD balance label 유지
- Tween만 사용. 신규 ParticleProcessMaterial 금지
- 토스트 kind `info|fail|warn` 기존 유지 — VFX는 병행
- 검수: 네 이벤트 육안으로 구분 가능하면 PASS

