# Testing Patterns

**Analysis Date:** 2026-04-14

## Test Framework

**Runner:** None — no test targets exist in the project.

No XCTest, Swift Testing (`@Test`), or third-party testing libraries are present. The `project.yml` XcodeGen spec defines only two targets (`KeyAuth` application and `KeyAuthKeyboard` app extension) with no test scheme targets. The Xcode scheme file at `KeyAuth.xcodeproj/xcshareddata/xcschemes/KeyAuth.xcscheme` contains no test action configuration.

**Run Commands:**
```bash
# No test commands are currently available.
# To add testing, create a test target in project.yml and run:
xcodebuild test -scheme KeyAuth -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Current Test Coverage

**Coverage: 0%** — No tests of any kind exist in this codebase.

## Testable Units

The following units are pure logic with no UIKit/SwiftUI dependencies and are the highest-priority candidates for testing:

**`Shared/TOTPGenerator.swift` — `enum TOTPGenerator`**
- `generate(secret:algorithm:digits:period:date:) -> String?`
- `generate(for:at:) -> String?`
- `secondsRemaining(period:at:) -> Int`
- These are pure functions with injected `date:` parameter, making them trivially testable without mocking.

**`Shared/Base32.swift` — `enum Base32`**
- `decode(_:) -> Data?`
- Pure function; test with known RFC 4648 base32 vectors and invalid inputs.

**`Shared/Account.swift` — `Account.from(otpauthURL:) -> Account?`**
- Static factory parsing `otpauth://totp/` URLs
- Pure function; test with valid, malformed, and edge-case URL strings.

**`Shared/KeychainManager.swift` — `KeychainManager`**
- `save(_:)`, `load(id:)`, `loadAll()`, `delete(id:)`, `deleteAll()`
- Requires Keychain entitlement; testable in a simulator with a dedicated test access group. Integration test, not unit test.

**`Shared/AccountStore.swift` — `AccountStore`**
- CRUD coordination layer over `KeychainManager`
- Requires a mock or stub `KeychainManager` for isolation; currently not injectable (hardcoded singleton).

## Recommended Test Structure

When tests are added, use this layout:

```
KeyAuthTests/               # New XCTest or Swift Testing target
├── TOTPGeneratorTests.swift
├── Base32Tests.swift
├── AccountURLParsingTests.swift
├── AccountStoreTests.swift
└── Helpers/
    └── MockKeychain.swift  # Protocol-based stub for KeychainManager
```

## Recommended Test Patterns

### Swift Testing (iOS 16+ target supports it via Xcode 15)

```swift
import Testing
@testable import KeyAuth

@Suite("TOTP Generator")
struct TOTPGeneratorTests {
    @Test("generates correct 6-digit TOTP for known secret and timestamp")
    func knownVector() throws {
        // RFC 6238 test vector: secret = "12345678901234567890", T=0, SHA1
        let secret = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: 59)
        let code = TOTPGenerator.generate(secret: secret, algorithm: .sha1, digits: 8, period: 30, date: date)
        #expect(code == "94287082")
    }

    @Test("returns nil for empty secret data")
    func emptySecret() {
        let code = TOTPGenerator.generate(secret: Data(), date: Date())
        #expect(code == nil)
    }

    @Test("secondsRemaining returns value within period")
    func secondsRemaining() {
        let remaining = TOTPGenerator.secondsRemaining(period: 30, at: Date(timeIntervalSince1970: 45))
        #expect(remaining == 15)
    }
}
```

### XCTest (alternative if Swift Testing is not preferred)

```swift
import XCTest
@testable import KeyAuth

final class Base32Tests: XCTestCase {
    func testDecodeKnownValue() {
        // "Hello!" in Base32 is "JBSWY3DPEB3W64TMMQ======"
        let result = Base32.decode("JBSWY3DPEB3W64TMMQ")
        XCTAssertEqual(result, "Hello!".data(using: .utf8))
    }

    func testDecodeInvalidCharacter() {
        XCTAssertNil(Base32.decode("INVALID!"))
    }

    func testDecodeEmptyString() {
        XCTAssertNil(Base32.decode(""))
    }
}
```

## Mocking

**Current barrier to mocking:** `AccountStore` uses a hardcoded singleton `KeychainManager.shared`. To make `AccountStore` testable in isolation, introduce a protocol:

```swift
// Proposed addition to Shared/KeychainManager.swift
protocol KeychainStoring {
    func save(_ account: Account) throws
    func load(id: UUID) throws -> Account?
    func loadAll() throws -> [Account]
    func delete(id: UUID) throws
}

extension KeychainManager: KeychainStoring {}

// Then update AccountStore:
@MainActor
final class AccountStore: ObservableObject {
    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainManager.shared) {
        self.keychain = keychain
        reload()
    }
}

// In tests:
final class MockKeychain: KeychainStoring {
    var accounts: [UUID: Account] = [:]

    func save(_ account: Account) throws { accounts[account.id] = account }
    func load(id: UUID) throws -> Account? { accounts[id] }
    func loadAll() throws -> [Account] { Array(accounts.values) }
    func delete(id: UUID) throws { accounts[id] = nil }
}
```

**What NOT to mock:**
- `TOTPGenerator`, `Base32`, `SharedDefaults` — these are pure or near-pure functions; test directly.
- `Account.from(otpauthURL:)` — test directly with URL literals.

## Test Types When Added

**Unit Tests (primary focus):**
- `TOTPGeneratorTests` — pure function, no I/O, date injected
- `Base32Tests` — pure function, no I/O
- `AccountURLParsingTests` — pure static factory, no I/O

**Integration Tests (secondary):**
- `AccountStoreTests` — requires `MockKeychain` to avoid real Keychain dependency
- `KeychainManager` round-trip — requires real simulator with entitlement, run in separate integration scheme

**UI/Snapshot Tests:**
- Not applicable with current architecture (no snapshot tooling present)

**E2E Tests:**
- Not applicable (no XCUITest infrastructure)

## Test Configuration When Added

Add to `project.yml`:
```yaml
  KeyAuthTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: KeyAuthTests
    dependencies:
      - target: KeyAuth
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.keyauth.app.tests
```

## Coverage Notes

These are the highest-risk untested paths in the current codebase:

| Area | Risk | Notes |
|------|------|-------|
| `TOTPGenerator.generate` | High | Core product feature; must match RFC 6238 |
| `Base32.decode` | High | All TOTP codes depend on this |
| `Account.from(otpauthURL:)` | High | QR scan produces accounts via this path |
| `AccountStore.move(from:to:)` | Medium | Index math is non-trivial |
| `AccountStore.delete(at:offsets:)` | Medium | Silent `try?` may swallow errors |
| `KeychainManager` encode/decode round-trip | Medium | Data corruption would be silent |
| `BiometricAuthManager` fallback logic | Low | OS-controlled; hard to unit test |

---

*Testing analysis: 2026-04-14*
