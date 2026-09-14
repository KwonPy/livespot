"""앱 전용 닉네임의 정규화·검증 (P30·P31, Q3-A).

**판정은 서버가 한다.** 앱에도 같은 규칙의 입력 검증이 있지만 그건 사용자 편의이고,
저장 여부를 정하는 것은 언제나 이 파일이다. 그래서 규칙을 라우터 두 곳
(`PUT /auth/me/nickname`, `GET /auth/nickname-available`)에 복붙하지 않고 여기 모았다 —
두 곳이 조금씩 갈리면 "확인할 땐 초록불이었는데 제출하면 빨간불"이 된다.

## 정규화를 왜 서버에서 하나 (P30)

① `strip()` — 앞뒤 공백. 눈에 보이지 않는 차이가 unique 제약을 그대로 통과한다.
② **유니코드 NFC** — 이쪽이 진짜 이유다. macOS/iOS 한글 입력은 자모 분해형(NFD)으로,
   Windows/Android는 조합형(NFC)으로 같은 글자를 만든다. 정규화하지 않으면 화면상
   **완전히 같은 "홍길동"** 두 개가 DB에서는 다른 바이트열이 되어 unique를 뚫는다.
   이건 클라이언트가 막을 수 있는 종류의 문제가 아니다.

## 허용 문자 (Q3-A 엄격)

한글 · 영문 · 숫자 · 밑줄(`_`)만. 2~12자.
한글은 완성형(`가-힣`)뿐 아니라 호환 자모(`ㄱ-ㅎ`, `ㅏ-ㅣ`)도 허용한다 — "ㅋㅋ" 같은 것도
사용자에게는 명백히 한글이고, 막으면 이유를 납득하기 어려운 거절이 된다.

공백·특수문자·이모지는 불가. 이 앱의 닉네임은 제보·답변 작성자 표시에 쓰이는
**신뢰도 라벨**이라 목록 레이아웃이 흔들리면 안 되고, 동형이의 문자로 남을 사칭하는
길도 열지 않는다. **나중에 푸는 것은 안전하지만 조이는 것은 불가능하다** — 이미 만들어진
닉네임을 고칠 관리자 도구가 이 프로젝트에 없다.

## 차단 목록을 붙일 자리

욕설·비속어 필터는 이번 범위가 아니다(명세 1절: 걸린 닉네임을 구제할 수단이 없다).
나중에 붙인다면 **`validate_nickname()` 안 한 곳**이다. 그래야 확인 API와 제출 API가
자동으로 같은 판정을 쓴다.
"""

import re
import unicodedata
from typing import Optional, Tuple

NICKNAME_MIN_LEN = 2
NICKNAME_MAX_LEN = 12

# 컬럼은 String(50) 그대로다 — 검증에서만 12자로 자른다(명세 Q3 각주).
# 컬럼 축소 마이그레이션은 위험 대비 이득이 없다.
_ALLOWED_RE = re.compile(r"^[0-9A-Za-z_가-힣ㄱ-ㅎㅏ-ㅣ]+$")

ERR_LENGTH = f"닉네임은 {NICKNAME_MIN_LEN}자 이상 {NICKNAME_MAX_LEN}자 이하로 입력해 주세요"
ERR_CHARSET = "닉네임에는 한글, 영문, 숫자, 밑줄(_)만 쓸 수 있어요"

# 중복 문구는 409(제출)와 nickname-available(조언) 양쪽이 쓴다. 두 곳의 문구가 갈리면
# 사용자가 "아까랑 다른 얘기"로 받아들인다.
ERR_DUPLICATE = "이미 사용 중인 닉네임이에요"


# 작성자 표시용 폴백 (P33). 선례: credit.py:225의 `else "게스트"`.
#
# **원칙적으로는 절대 쓰이지 않아야 하는 값이다.** 닉네임 미설정 사용자는 아무것도 쓸 수
# 없으므로(P28) 작성자로 등장할 수 없다. 그런데도 두는 이유는, 그 불변식이 깨졌을 때
# (마이그레이션 사고, DB 직접 수정, 앞으로 생길 관리자 도구) **목록 조회 전체가
# ResponseValidationError로 500이 나는 것보다 한 줄이 "알 수 없음"으로 뜨는 편이 낫기**
# 때문이다. 이 값이 화면에 보인다면 그 자체가 버그 신호다.
UNKNOWN_NICKNAME = "알 수 없음"


def display_nickname(value: Optional[str]) -> str:
    """조인 결과의 nullable 닉네임 → 응답에 실을 non-null 문자열 (P33).

    `ReportResponse.user_nickname` 등 작성자 표시 필드는 계속 `str`(비-null)이다 —
    앱이 "작성자 이름이 없을 수도 있다"를 매 화면에서 분기하게 만들지 않기 위해서다.
    """
    return value or UNKNOWN_NICKNAME


def normalize_nickname(raw: str) -> str:
    """저장·비교에 쓸 표준형으로 만든다. **DB에 들어가는 값은 언제나 이 함수의 출력이다.**

    검증 전에 먼저 부른다 — 길이도 문자 검사도 정규화된 문자열 기준이어야
    "화면에 보이는 12자"와 "서버가 센 12자"가 일치한다.
    """
    return unicodedata.normalize("NFC", (raw or "").strip())


def validate_nickname(raw: str) -> Tuple[str, Optional[str]]:
    """(정규화된 닉네임, 에러 문구 또는 None).

    예외를 던지지 않고 문구를 돌려주는 이유: 호출자 둘의 처리가 다르다 —
    제출은 400으로 올리고, 확인 API는 200 본문의 `reason`에 담는다.
    예외로 만들면 확인 API가 자기 예외를 자기가 잡는 모양이 된다.

    반환하는 문구는 **화면에 그대로 띄울 수 있는 한국어**다(2-4절: Pydantic 422 리스트
    형식에 의존하지 않는다).
    """
    nickname = normalize_nickname(raw)

    # 길이를 코드포인트로 센다. 한글 1자 = 1로 세야 사용자가 센 것과 같다.
    if not (NICKNAME_MIN_LEN <= len(nickname) <= NICKNAME_MAX_LEN):
        return nickname, ERR_LENGTH

    if not _ALLOWED_RE.match(nickname):
        return nickname, ERR_CHARSET

    return nickname, None
