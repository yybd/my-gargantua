import Foundation
import GargantuaCore
import SwiftUI

// Root content view for the Gargantua window.
//
// Fills the entire window with `GargantuaColors.void_` so no system
// chrome is visible behind the transparent titlebar. Shows the permission
// request flow on first launch, then sidebar + content.
//
// AI-engine state, handler closures, and persistence resolution live in
// `MainContentView+Wiring`; stored properties are internal (not private) so
// that extension can reach them.
struct MainContentView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage(AIEnginePreference.userDefaultsKey) var preferredAIEngineRawValue = AIEnginePreference.template.rawValue
    @State var sidebarSelection: String? = "dashboard"
    /// Plist path the Process Inventory pane asked Background Items to
    /// pre-select. Set when the user clicks "Open source" on a launchd-backed
    /// process; the Background Items view consumes + clears it once it lands
    /// on the matching row.
    @State var pendingBackgroundItemPlistPath: String?
    @State var persistence: PersistenceController?
    @State var dashboardSession = DashboardSessionState()
    @State var deepCleanSession = DeepCleanSessionState()
    @State var smartUninstallerViewModel = SmartUninstallerView.makeDefaultViewModel()
    @State var fileHealthState = FileHealthContainerState()
    @State var duplicateFinderState = DuplicateFinderContainerState()
    @State var duplicateFinderSelection: Set<String> = []
    @State var diskExplorerState = DiskExplorerState()
    @State var aiModelsSession = AIModelsState()
    @State var devToolsSession = DeveloperToolsSessionState()
    @State var backgroundItemsSession = BackgroundItemsSession()
    @State var processInventorySession = ProcessInventorySession()
    @StateObject var organizerSession: OrganizerSessionState
    @StateObject var cloudAIService: CloudAIService
    @State var activeAIEngineKind: AIEnginePreference

    // App-shared AI plumbing. One `ModelDownloadManager` so Settings' download
    // button + every scan view's "model available?" check observe the same
    // state; one `LocalAIService` so the engine lazy-load / 60-s idle-unload
    // lifecycle doesn't reset between screens; one `AIExplanationController`
    // so the presentation sheet can render at this top level regardless of
    // which scan view fired `onExplain`.
    @StateObject var downloadManager: ModelDownloadManager
    @StateObject var aiService: LocalAIService
    @StateObject var aiExplanation: AIExplanationController
    @StateObject var aiAdvisory: AIAdvisoryController
    @StateObject var mcpStatusModel: MCPServerStatusViewModel
    let updateSettingsViewModel: AppUpdateSettingsViewModel

    init(updateSettingsViewModel: AppUpdateSettingsViewModel) {
        let manager = ModelDownloadManager()
        let selectedEngine = AIInferenceEngineFactory.select(
            preference: AIEnginePreference.stored(),
            modelState: manager.state
        )
        self.updateSettingsViewModel = updateSettingsViewModel
        let service = LocalAIService(downloadManager: manager, engine: selectedEngine.engine)
        _activeAIEngineKind = State(initialValue: selectedEngine.kind)
        _downloadManager = StateObject(wrappedValue: manager)
        _aiService = StateObject(wrappedValue: service)
        _aiExplanation = StateObject(wrappedValue: AIExplanationController(service: service))
        _aiAdvisory = StateObject(wrappedValue: AIAdvisoryController(service: service))
        _mcpStatusModel = StateObject(wrappedValue: MCPServerStatusViewModel())

        let cloudAI = CloudAIService()
        let mlxProposer = MLXOrganizerProposer(aiService: service)
        _cloudAIService = StateObject(wrappedValue: cloudAI)
        _organizerSession = StateObject(wrappedValue: OrganizerSessionState(
            cloudService: cloudAI,
            mlxProposer: mlxProposer
        ))
    }

    var body: some View {
        ZStack {
            GargantuaColors.void_
                .ignoresSafeArea()

            if !hasCompletedOnboarding {
                PermissionRequestFlowView(isComplete: $hasCompletedOnboarding)
            } else {
                HStack(spacing: 0) {
                    SidebarView(selection: $sidebarSelection, mcpStatusModel: mcpStatusModel)

                    // Content area
                    VStack(spacing: 0) {
                        if !PermissionChecker.hasFullDiskAccess {
                            PermissionBannerView.fullDiskAccess
                                .padding(.horizontal, GargantuaSpacing.space4)
                                .padding(.top, GargantuaSpacing.space3)
                        }

                        Group {
                            switch sidebarSelection {
                            case "dashboard":
                                DashboardView(
                                    sidebarSelection: $sidebarSelection,
                                    session: dashboardSession,
                                    persistence: persistence
                                )
                            case "profiles":
                                if let persistence {
                                    ProfileContainerView(persistence: persistence)
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            case "deepClean":
                                DeepCleanView(
                                    profile: activeDeepCleanProfile,
                                    session: deepCleanSession,
                                    staleVersionPinnedPaths: pathExclusionPatterns,
                                    onExplain: explainHandler,
                                    onAdvisory: advisoryHandler,
                                    onResolveFilter: scanFilterHandler,
                                    onCleanupCompleted: dashboardCleanupHandler
                                )
                            case "smartUninstaller":
                                SmartUninstallerView(viewModel: smartUninstallerViewModel)
                            case "duplicateFinder":
                                DuplicateFinderContainerView(
                                    state: duplicateFinderState,
                                    scanRoots: resolvedScanRoots,
                                    selectedIDs: $duplicateFinderSelection,
                                    onExplain: explainHandler,
                                    persistence: persistence,
                                    onCleanupCompleted: dashboardCleanupHandler
                                )
                            case "fileOrganizer":
                                FileOrganizerView(
                                    session: organizerSession,
                                    mlxAvailabilityProvider: { isMLXOrganizerReady }
                                )
                            case "fileHealth":
                                FileHealthContainerView(
                                    state: fileHealthState,
                                    scanRoots: resolvedScanRoots,
                                    profile: activeDeepCleanProfile,
                                    onExplain: explainHandler,
                                    onSuggestClusters: clusterSuggestionHandler
                                )
                            case "diskExplorer":
                                DiskExplorerView(state: diskExplorerState)
                            case "aiModels":
                                AIModelsView(
                                    profile: .aiModels,
                                    scanRoots: resolvedScanRoots,
                                    aiModelExcludedPaths: pathExclusionPatterns,
                                    session: aiModelsSession,
                                    onExplain: explainHandler,
                                    onAdvisory: advisoryHandler,
                                    onResolveFilter: scanFilterHandler
                                )
                            case "backgroundItems":
                                BackgroundItemsView(
                                    session: backgroundItemsSession,
                                    onExplain: explainHandler,
                                    onTriage: triageHandler,
                                    preSelectedPlistPath: $pendingBackgroundItemPlistPath
                                )
                            case "processInventory":
                                ProcessInventoryView(
                                    session: processInventorySession,
                                    onExplain: explainHandler,
                                    onTriage: triageHandler,
                                    onNavigateToBackgroundItems: { plistPath in
                                        pendingBackgroundItemPlistPath = plistPath
                                        sidebarSelection = "backgroundItems"
                                    }
                                )
                            case "rules":
                                if let persistence {
                                    RuleViewerView(
                                        persistence: persistence,
                                        updateSettingsViewModel: updateSettingsViewModel
                                    )
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            case "devPurge":
                                DevArtifactScanView(
                                    profile: .devPurge,
                                    scanRoots: resolvedScanRoots,
                                    staleVersionPinnedPaths: pathExclusionPatterns,
                                    onExplain: explainHandler,
                                    onResolveFilter: scanFilterHandler,
                                    onCleanupCompleted: dashboardCleanupHandler,
                                    onOpenDeveloperTools: { sidebarSelection = "devTools" }
                                )
                            case "devTools":
                                DeveloperToolsView(session: devToolsSession)
                            case "agentSessions":
                                ClaudeCodeAgentView()
                            case "settings":
                                if let persistence {
                                    SettingsView(
                                        persistence: persistence,
                                        downloadManager: downloadManager,
                                        updateSettingsViewModel: updateSettingsViewModel
                                    )
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            default:
                                placeholderView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.cleanupNarrator, narrateHandler)
                .environment(\.activeAIEngineKind, activeAIEngineKind)
                .environment(\.preferredAIEngineKind, preferredAIEngine)
                .environment(\.aiEngineNeedsFirstWarmup, aiEngineNeedsFirstWarmup)
                .environment(\.openAIModelSettings, { sidebarSelection = "settings" })
                .onAppear {
                    initializePersistenceIfNeeded()
                    refreshAIEngineSelection()
                }
                .onChange(of: preferredAIEngineRawValue) { _, _ in
                    refreshAIEngineSelection()
                }
                .onChange(of: downloadManager.state) { _, _ in
                    refreshAIEngineSelection()
                }
                .sheet(item: Binding(
                    get: { aiExplanation.presentation },
                    set: { if $0 == nil { aiExplanation.dismiss() } }
                )) { _ in
                    AIExplanationSheet(
                        controller: aiExplanation,
                        onOpenSettings: { sidebarSelection = "settings" }
                    )
                }
                .sheet(item: Binding(
                    get: { aiAdvisory.presentation },
                    set: { if $0 == nil { aiAdvisory.dismiss() } }
                )) { _ in
                    AIAdvisorySheet(
                        controller: aiAdvisory,
                        onOpenSettings: { sidebarSelection = "settings" }
                    )
                }
            }
        }
    }
}
