import Foundation

/// `/admin/me` `auth_method` (00 §1.9). Values this App does not know are kept, not rejected.
public enum AdminAuthMethod: Hashable, Sendable, Decodable {
    case jwt, adminAPIKey, adminAccessToken, other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "jwt": self = .jwt
        case "admin_api_key": self = .adminAPIKey
        case "admin_access_token": self = .adminAccessToken
        default: self = .other(rawValue)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public var rawValue: String {
        switch self {
        case .jwt: "jwt"
        case .adminAPIKey: "admin_api_key"
        case .adminAccessToken: "admin_access_token"
        case .other(let value): value
        }
    }
    /// Admin Key and `sat_`: no step-up and no session list (backend `IsMachineCredential`).
    public var isMachineCredential: Bool { self == .adminAPIKey || self == .adminAccessToken }
    /// The only inference for a missing `auth_method` (D09): the reported value wins, otherwise the credential kind decides.
    public static func resolved(reported: AdminAuthMethod?, credential: Credential?) -> AdminAuthMethod? {
        if let reported { return reported }
        switch credential {
        case .tokens: return .jwt
        case .adminKey: return .adminAPIKey
        case .accessToken: return .adminAccessToken
        case nil: return nil
        }
    }
}

/// 00 §5: backend `adminMeCapabilities` plus the embedded-Web `web.accounts_edit_deep_link`. Check with `AdminMe.has(_:)`.
public enum Capability: String, CaseIterable, Sendable {
    case accountsApplyOAuthPreserveStatus = "accounts.apply_oauth_preserve_status"
    case accountsClearErrorPreserveInactive = "accounts.clear_error_preserve_inactive"
    case accountsListQuery = "accounts.list_query"
    case accountsMixedChannelDetails = "accounts.mixed_channel_details"
    case accountsOAuthErrorReasons = "accounts.oauth_error_reasons"
    case accountsPatch = "accounts.patch"
    case accountsReauthorize = "accounts.reauthorize"
    case accountsRecoverSchedulable = "accounts.recover_schedulable"
    case accountsRuntimeBatch = "accounts.runtime_batch"
    case adminAccessTokens = "admin.access_tokens"
    case adminIdempotentWrites = "admin.idempotent_writes"
    case accountsStatusSummary = "accounts.status_summary"
    case accountsStructuredError = "accounts.structured_error"
    case accountsTestResult = "accounts.test_result"
    case accountsTestRuns = "accounts.test_runs"
    case accountsTodayStatsFailures = "accounts.today_stats_failures"
    case accountsTodayStatsGroup = "accounts.today_stats_group"
    case accountsTokenStatus = "accounts.token_status"
    case announcementsIdempotentCreate = "announcements.idempotent_create"
    case announcementsReadStats = "announcements.read_stats"
    case apiKeysCurrentConcurrency = "api_keys.current_concurrency"
    case apiKeysEffectiveStatus = "api_keys.effective_status"
    case apiKeysMaskedView = "api_keys.masked_view"
    case authCaptchaProvider = "auth.captcha_provider"
    case dashboardAccountCost = "dashboard.account_cost"
    case dashboardAccountsRanking = "dashboard.accounts_ranking"
    case dashboardHome = "dashboard.home"
    case dashboardRates = "dashboard.rates"
    case dashboardRequestTypes = "dashboard.request_types"
    case dashboardUsersRankingSort = "dashboard.users_ranking_sort"
    case dashboardUsersTrendFilteredMetric = "dashboard.users_trend_filtered_metric"
    case groupsAccountBuckets = "groups.account_buckets"
    case groupsCapacityFilter = "groups.capacity_filter"
    case groupsMemberBatch = "groups.member_batch"
    case listsETag = "lists.etag"
    case logsSinceID = "logs.since_id"
    case metaCatalog = "meta.catalog"
    case opsAlertEventCounts = "ops.alert_event_counts"
    case opsAlertEventDetails = "ops.alert_event_details"
    case opsAlertLatencyMetrics = "ops.alert_latency_metrics"
    case opsDashboardModelFilter = "ops.dashboard_model_filter"
    case opsIngressRejectTotals = "ops.ingress_reject_totals"
    case opsJobHeartbeatStatus = "ops.job_heartbeat_status"
    case opsMonitoringStatus = "ops.monitoring_status"
    case opsRequestAttempts = "ops.request_attempts"
    case opsSystemMetricsHistory = "ops.system_metrics_history"
    case opsTokenStatsCustomRange = "ops.token_stats_custom_range"
    case proxiesFallbackAccounts = "proxies.fallback_accounts"
    case pushNotifications = "push.notifications"
    case redeemCodesDeleteGuard = "redeem_codes.delete_guard"
    case redeemCodesStats = "redeem_codes.stats"
    case scheduledTestsUpstreamStatus = "scheduled_tests.upstream_status"
    case usageModelSource = "usage.model_source"
    case usersBalanceLedger = "users.balance_ledger"
    case usersPlatformQuotaItem = "users.platform_quota_item"
    case usersQuickTopup = "users.quick_topup"
    case usersRPMTracked = "users.rpm_tracked"
    case webAccountsEditDeepLink = "web.accounts_edit_deep_link"
}

/// `GET /api/v1/admin/me` (00 §1.9). Every field may be missing: nil means unknown, never false or 0.
public struct AdminMe: Decodable, Sendable, Equatable {
    public struct User: Decodable, Sendable, Equatable {
        public let id: Int?
        public let email: String?
        public let username: String?
        public let role: String?
        public init(id: Int? = nil, email: String? = nil, username: String? = nil, role: String? = nil) {
            self.id = id; self.email = email; self.username = username; self.role = role
        }
    }
    public struct WorkspacePermissions: Decodable, Sendable, Equatable {
        public let accountManage, groupOps, groupBilling, proxyManage, monitorView: Bool?
        public init(accountManage: Bool? = nil, groupOps: Bool? = nil, groupBilling: Bool? = nil, proxyManage: Bool? = nil, monitorView: Bool? = nil) {
            self.accountManage = accountManage; self.groupOps = groupOps; self.groupBilling = groupBilling
            self.proxyManage = proxyManage; self.monitorView = monitorView
        }
        enum CodingKeys: String, CodingKey {
            case accountManage = "account_manage", groupOps = "group_ops", groupBilling = "group_billing"
            case proxyManage = "proxy_manage", monitorView = "monitor_view"
        }
    }
    /// Only vendors have one; null for admin.
    public struct Workspace: Decodable, Sendable, Equatable {
        public let id: Int?
        public let name: String?
        public let permissions: WorkspacePermissions?
        public init(id: Int? = nil, name: String? = nil, permissions: WorkspacePermissions? = nil) {
            self.id = id; self.name = name; self.permissions = permissions
        }
    }
    public struct Security: Decodable, Sendable, Equatable {
        public let totpEnabled, stepUpEnabled, stepUpAvailable, stepUpGranted: Bool?
        public let stepUpExpiresIn: Int?
        public let sessionBindingEnabled: Bool?
        public init(totpEnabled: Bool? = nil, stepUpEnabled: Bool? = nil, stepUpAvailable: Bool? = nil, stepUpGranted: Bool? = nil,
                    stepUpExpiresIn: Int? = nil, sessionBindingEnabled: Bool? = nil) {
            self.totpEnabled = totpEnabled; self.stepUpEnabled = stepUpEnabled; self.stepUpAvailable = stepUpAvailable
            self.stepUpGranted = stepUpGranted; self.stepUpExpiresIn = stepUpExpiresIn; self.sessionBindingEnabled = sessionBindingEnabled
        }
        enum CodingKeys: String, CodingKey {
            case totpEnabled = "totp_enabled", stepUpEnabled = "step_up_enabled", stepUpAvailable = "step_up_available"
            case stepUpGranted = "step_up_granted", stepUpExpiresIn = "step_up_expires_in", sessionBindingEnabled = "session_binding_enabled"
        }
    }
    public struct Compliance: Decodable, Sendable, Equatable {
        public let required: Bool?
        public let version: String?
        public init(required: Bool? = nil, version: String? = nil) { self.required = required; self.version = version }
    }
    public struct Features: Decodable, Sendable, Equatable {
        public let opsMonitoringEnabled, opsRealtimeMonitoringEnabled: Bool?
        /// `config_off` / `setting_off`; null while monitoring is on.
        public let opsMonitoringDisabledReason: String?
        public let channelMonitorEnabled: Bool?
        public let channelMonitorMode: String?
        public let backendModeEnabled, paymentEnabled, subscriptionEnabled: Bool?
        public init(opsMonitoringEnabled: Bool? = nil, opsRealtimeMonitoringEnabled: Bool? = nil, opsMonitoringDisabledReason: String? = nil,
                    channelMonitorEnabled: Bool? = nil, channelMonitorMode: String? = nil, backendModeEnabled: Bool? = nil,
                    paymentEnabled: Bool? = nil, subscriptionEnabled: Bool? = nil) {
            self.opsMonitoringEnabled = opsMonitoringEnabled; self.opsRealtimeMonitoringEnabled = opsRealtimeMonitoringEnabled
            self.opsMonitoringDisabledReason = opsMonitoringDisabledReason; self.channelMonitorEnabled = channelMonitorEnabled
            self.channelMonitorMode = channelMonitorMode; self.backendModeEnabled = backendModeEnabled
            self.paymentEnabled = paymentEnabled; self.subscriptionEnabled = subscriptionEnabled
        }
        enum CodingKeys: String, CodingKey {
            case opsMonitoringEnabled = "ops_monitoring_enabled", opsRealtimeMonitoringEnabled = "ops_realtime_monitoring_enabled"
            case opsMonitoringDisabledReason = "ops_monitoring_disabled_reason", channelMonitorEnabled = "channel_monitor_enabled"
            case channelMonitorMode = "channel_monitor_mode", backendModeEnabled = "backend_mode_enabled"
            case paymentEnabled = "payment_enabled", subscriptionEnabled = "subscription_enabled"
        }
    }
    public struct Server: Decodable, Sendable, Equatable {
        public let version, runMode, serverTimezone, serverUTCOffset: String?
        /// Unknown strings are kept; a missing or null list is empty.
        public let capabilities: Set<String>
        public init(version: String? = nil, runMode: String? = nil, serverTimezone: String? = nil, serverUTCOffset: String? = nil,
                    capabilities: Set<String> = []) {
            self.version = version; self.runMode = runMode; self.serverTimezone = serverTimezone
            self.serverUTCOffset = serverUTCOffset; self.capabilities = capabilities
        }
        enum CodingKeys: String, CodingKey {
            case version, runMode = "run_mode", serverTimezone = "server_timezone", serverUTCOffset = "server_utc_offset", capabilities
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version); runMode = try c.decodeIfPresent(String.self, forKey: .runMode)
            serverTimezone = try c.decodeIfPresent(String.self, forKey: .serverTimezone)
            serverUTCOffset = try c.decodeIfPresent(String.self, forKey: .serverUTCOffset)
            capabilities = Set(try c.decodeIfPresent([String].self, forKey: .capabilities) ?? [])
        }
    }

    public let authMethod: AdminAuthMethod?
    public let user: User?
    public let workspace: Workspace?
    public let security: Security
    public let compliance: Compliance
    public let features: Features
    public let server: Server
    /// Assembled from the old-server probes instead of `/admin/me`; never decoded.
    public let isLegacyServer: Bool

    public init(authMethod: AdminAuthMethod? = nil, user: User? = nil, workspace: Workspace? = nil, security: Security = .init(),
                compliance: Compliance = .init(), features: Features = .init(), server: Server = .init(), isLegacyServer: Bool = false) {
        self.authMethod = authMethod; self.user = user; self.workspace = workspace; self.security = security
        self.compliance = compliance; self.features = features; self.server = server; self.isLegacyServer = isLegacyServer
    }
    enum CodingKeys: String, CodingKey { case authMethod = "auth_method", user, workspace, security, compliance, features, server }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authMethod = try c.decodeIfPresent(AdminAuthMethod.self, forKey: .authMethod)
        user = try c.decodeIfPresent(User.self, forKey: .user); workspace = try c.decodeIfPresent(Workspace.self, forKey: .workspace)
        security = try c.decodeIfPresent(Security.self, forKey: .security) ?? Security()
        compliance = try c.decodeIfPresent(Compliance.self, forKey: .compliance) ?? Compliance()
        features = try c.decodeIfPresent(Features.self, forKey: .features) ?? Features()
        server = try c.decodeIfPresent(Server.self, forKey: .server) ?? Server()
        isLegacyServer = false
    }

    public var capabilities: Set<String> { server.capabilities }
    public func has(_ capability: Capability) -> Bool { server.capabilities.contains(capability.rawValue) }
    /// The only administrator rule (D09): admin role outside any workspace. An old server's Admin Key or `sat_`
    /// probe proves admin rights without returning a user.
    public var isAdministrator: Bool {
        if let role = user?.role { return role == "admin" && workspace == nil }
        return user == nil && authMethod?.isMachineCredential == true
    }
}

/// `GET /api/v1/auth/me` on servers that predate `/admin/me`.
struct LegacyAuthMe: Decodable, Sendable {
    let id: Int?
    let email: String?
    let username: String?
    let role: String?
    let runMode: String?
    let workspace: AdminMe.Workspace?
    enum CodingKeys: String, CodingKey { case id, email, username, role, runMode = "run_mode", workspace }
}

extension AdminMe {
    /// 00 §1.9 old server: no capabilities, monitoring assumed on until a block answers `OPS_DISABLED`, security unknown.
    static func legacy(authMethod: AdminAuthMethod, authMe: LegacyAuthMe?, settings: PublicSettings?, compliance: AdminComplianceStatus?) -> AdminMe {
        AdminMe(authMethod: authMethod,
                user: authMe.map { User(id: $0.id, email: $0.email, username: $0.username, role: $0.role) },
                workspace: authMe?.workspace,
                compliance: Compliance(required: compliance?.required, version: compliance?.version),
                features: Features(opsMonitoringEnabled: true, opsRealtimeMonitoringEnabled: true,
                                   channelMonitorEnabled: settings?.channelMonitorEnabled, channelMonitorMode: settings?.channelMonitorMode,
                                   backendModeEnabled: settings?.backendModeEnabled, paymentEnabled: settings?.paymentEnabled,
                                   subscriptionEnabled: settings?.subscriptionEnabled),
                server: Server(version: settings?.version, runMode: authMe?.runMode, serverTimezone: settings?.serverTimezone,
                               serverUTCOffset: settings?.serverUTCOffset),
                isLegacyServer: true)
    }
}

extension APIClient {
    /// Replaces the old realtime probe. Only a non-JSON 404 (`.unsupported`) means the server predates `/admin/me`;
    /// a JSON 404, 401 and 403 are thrown unchanged.
    public func me() async throws -> AdminMe {
        let credential = try probeCredential()
        let snapshot = currentGeneration()
        let result: AdminMe
        do { result = try await request("admin/me", timeout: RequestTimeout.probe) }
        catch let error as APIError where error.kind == .unsupported { result = try await legacyMe(credential) }
        try check(snapshot)
        await setConditionalCacheIdentity(ConditionalCache.Identity(me: result, credential: credential))
        try check(snapshot)
        return result
    }

    private func probeCredential() throws -> Credential {
        guard let credential = currentCredential() else { throw APIError.authenticationRequired }
        switch credential {
        case .adminKey(let key), .accessToken(let key):
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.authenticationRequired }
        case .tokens: break
        }
        return credential
    }

    private func legacyMe(_ credential: Credential) async throws -> AdminMe {
        async let settings = optionalPublicSettings()
        guard case .tokens = credential else {
            let method: AdminAuthMethod = credential.authenticationKind == .accessToken ? .adminAccessToken : .adminAPIKey
            // admin/compliance skips the compliance guard, so it is the permission probe. Sites older than it
            // (before 2026-06) have no guard either, and the realtime read is still a valid probe there.
            let compliance = try await optionalCompliance()
            if compliance == nil { let _: EmptyReply = try await request("admin/dashboard/realtime", timeout: RequestTimeout.probe) }
            let publicSettings = try await settings
            return AdminMe.legacy(authMethod: method, authMe: nil, settings: publicSettings, compliance: compliance)
        }
        async let authMe: LegacyAuthMe = request("auth/me", timeout: RequestTimeout.probe)
        async let compliance = optionalCompliance()
        // auth/me carries identity and role, so its failure is the failure of me().
        let user = try await authMe
        let status = try await compliance
        let publicSettings = try await settings
        return AdminMe.legacy(authMethod: .jwt, authMe: user, settings: publicSettings, compliance: status)
    }

    /// Unauthenticated and only fills version, time zone and module switches: any failure leaves them unknown.
    private func optionalPublicSettings() async throws -> PublicSettings? {
        do {
            let settings: PublicSettings = try await request("settings/public", authenticated: false, timeout: RequestTimeout.probe)
            return settings
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }

    /// A non-JSON 404 means the site predates admin/compliance; every other failure is a real answer about the credential.
    private func optionalCompliance() async throws -> AdminComplianceStatus? {
        do { return try await complianceStatus() }
        catch let error as APIError where error.kind == .unsupported { return nil }
    }
}
