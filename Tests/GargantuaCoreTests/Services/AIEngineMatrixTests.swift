import Foundation
import Testing
@testable import GargantuaCore

@Suite("AIEngineMatrix")
struct AIEngineMatrixTests {
    @Test("Inline and organize accept every engine")
    func inlineAndOrganizeAcceptAll() {
        for useCase in [AIUseCase.inlineExplain, .organize] {
            for engine in AIEngineID.allCases {
                #expect(useCase.canUse(engine))
                #expect(useCase.disabledReason(for: engine) == nil)
            }
        }
    }

    @Test("Deeper explain rejects local engines with a reason, accepts the rest")
    func deeperRejectsLocal() {
        #expect(!AIUseCase.deeperExplain.canUse(.template))
        #expect(!AIUseCase.deeperExplain.canUse(.mlx))
        #expect(AIUseCase.deeperExplain.disabledReason(for: .template) != nil)
        #expect(AIUseCase.deeperExplain.disabledReason(for: .mlx) != nil)
        for engine in [AIEngineID.cloud, .claudeCode, .codex] {
            #expect(AIUseCase.deeperExplain.canUse(engine))
            #expect(AIUseCase.deeperExplain.disabledReason(for: engine) == nil)
        }
    }

    @Test("Maintenance accepts the two agentic engines; local + cloud are greyed with a reason")
    func maintenanceAcceptsAgenticEngines() {
        for engine in [AIEngineID.template, .mlx, .cloud] {
            #expect(!AIUseCase.maintenance.canUse(engine))
            #expect(AIUseCase.maintenance.disabledReason(for: engine) != nil)
        }
        for engine in [AIEngineID.claudeCode, .codex] {
            #expect(AIUseCase.maintenance.canUse(engine))
            #expect(AIUseCase.maintenance.disabledReason(for: engine) == nil)
        }
    }

    @Test("Every use case's default engine can serve it")
    func defaultsAreValid() {
        for useCase in AIUseCase.allCases {
            #expect(useCase.canUse(useCase.defaultEngine))
        }
    }

    @Test("Only Template and MLX report as local")
    func localFlag() {
        #expect(AIEngineID.template.isLocal)
        #expect(AIEngineID.mlx.isLocal)
        for engine in [AIEngineID.cloud, .claudeCode, .codex] {
            #expect(!engine.isLocal)
        }
    }
}
