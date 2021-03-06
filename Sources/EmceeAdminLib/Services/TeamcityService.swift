import AtomicModels
import Foundation
import Services
import SocketModels
import TeamcityApi

public final class TeamcityService: Service, CustomStringConvertible {
    enum StateId: String {
        case isAuthorized
        case isEnabled
        case isConnected
    }
    
    enum ActionId: String {
        case enableAgent
        case disableAgent
    }
    
    private let agentPoolIds: [Int]
    private let teamcityConfig: TeamcityConfig
    private let callbackQueue = DispatchQueue(label: "TeamcityService.callbackQueue")
    private var agentsWithDetails = AtomicValue([TeamcityAgentWithDetails]())
    public let version: String
    private let teamcityRequestProvider: TeamcityRequestProvider
    
    public init(
        agentPoolIds: [Int],
        teamcityConfig: TeamcityConfig,
        version: String,
        teamcityRequestProvider: TeamcityRequestProvider
    ) {
        self.agentPoolIds = agentPoolIds
        self.teamcityConfig = teamcityConfig
        self.version = version
        self.teamcityRequestProvider = teamcityRequestProvider
    }
    
    public var name: String {
        "TeamCity"
    }
    
    public var socketAddress: SocketAddress {
        let url = teamcityConfig.teamcityApiEndpoint
        return SocketAddress(
            host: url.host ?? "unknown",
            port: SocketModels.Port(
                value: url.port ?? (url.scheme == "https" ? 443 : 80)
            )
        )
    }
    
    public var serviceWorkers: [ServiceWorker] {
        agentsWithDetails.currentValue().map {
            TeamcityAgent(teamcityAgentWithDetails: $0)
        }
    }
    
    public func updateWorkers() {
        let provider = DefaultTeamcityRequestProvider(
            restApiEndpoint: teamcityConfig.teamcityApiEndpoint,
            session: DefaultTeamcitySessionProvider(teamcityConfig: teamcityConfig).createSession()
        )
        
        let fetchedAgentsWithDetails = AtomicValue([TeamcityAgentWithDetails]())
        
        let group = DispatchGroup()
        
        for poolId in agentPoolIds {
            group.enter()
            
            provider.fetchAgentPool(poolId: poolId) { (response: Result<TeamcityAgentPool, Error>) in
                defer { group.leave() }
                
                guard let agentPool = try? response.get() else { return }
                for agentInPool in agentPool.agentsInPool {
                    group.enter()
                    provider.fetchAgentDetails(agentId: agentInPool.id) { (response: Result<TeamcityAgentWithDetails, Error>) in
                        defer { group.leave() }
                        
                        guard let agentWithDetails = try? response.get() else { return }
                        fetchedAgentsWithDetails.withExclusiveAccess { $0.append(agentWithDetails) }
                    }
                }
            }
        }
        
        group.wait()
        agentsWithDetails.set(fetchedAgentsWithDetails.currentValue())
    }
    
    public var description: String { "<\(type(of: self)) agentPoolIds=\(agentPoolIds) \(serviceWorkers)>" }
    
    public func execute(action: ServiceWorkerAction, serviceWorker: ServiceWorker) {
        guard let serviceWorker = serviceWorker as? TeamcityAgent else { return }
        guard let action = action as? TeamcityAgentAction else { return }

        let group = DispatchGroup()
        group.enter()
        
        switch action.actionId {
        case .disableAgent:
            teamcityRequestProvider.disableAgent(agentId: serviceWorker.teamcityAgentWithDetails.id) { error in
                group.leave()
            }
        case .enableAgent:
            teamcityRequestProvider.enableAgent(agentId: serviceWorker.teamcityAgentWithDetails.id) { error in
                group.leave()
            }
        }
        
        group.wait()
    }
}

final class TeamcityAgent: ServiceWorker, CustomStringConvertible {
    let teamcityAgentWithDetails: TeamcityAgentWithDetails
    
    init(
        teamcityAgentWithDetails: TeamcityAgentWithDetails
    ) {
        self.teamcityAgentWithDetails = teamcityAgentWithDetails
    }
    
    var id: String { "\(teamcityAgentWithDetails.id)" }
    
    var name: String { teamcityAgentWithDetails.name }
    
    var states: [ServiceWorkerState] {
        [
            TeamcityAgentState(stateId: .isAuthorized, name: "Authorized", status: teamcityAgentWithDetails.authorized ? "Authrorized" : "Not Authorized", isPositive: teamcityAgentWithDetails.authorized),
            TeamcityAgentState(stateId: .isConnected, name: "Connected", status: teamcityAgentWithDetails.connected ? "Connected" : "Disconnected", isPositive: teamcityAgentWithDetails.connected),
            TeamcityAgentState(stateId: .isEnabled, name: "Enabled", status: teamcityAgentWithDetails.enabled ? "Enabled" : "Disabled", isPositive: teamcityAgentWithDetails.enabled),
        ]
    }
    
    var actions: [ServiceWorkerAction] {
        var actions = [TeamcityAgentAction]()
        if teamcityAgentWithDetails.enabled {
            actions.append(TeamcityAgentAction(actionId: .disableAgent, name: "Disable \(teamcityAgentWithDetails.name)"))
        } else {
            actions.append(TeamcityAgentAction(actionId: .enableAgent, name: "Enable \(teamcityAgentWithDetails.name)"))
        }
        return actions
    }
    
    var description: String { "<\(type(of: self)) \(id) states=\(states) actions=\(actions)>" }
}

final class TeamcityAgentState: ServiceWorkerState, CustomStringConvertible {
    let id: String
    let name: String
    let status: String
    let isPositive: Bool
    
    init(
        stateId: TeamcityService.StateId,
        name: String,
        status: String,
        isPositive: Bool
    ) {
        self.id = stateId.rawValue
        self.name = name
        self.status = status
        self.isPositive = isPositive
    }
    
    var description: String { "<\(id) \(status)>" }
}

final class TeamcityAgentAction: ServiceWorkerAction, CustomStringConvertible {
    let actionId: TeamcityService.ActionId
    let name: String
    
    init(actionId: TeamcityService.ActionId, name: String) {
        self.actionId = actionId
        self.name = name
    }
    
    var id: String { actionId.rawValue }
    
    var description: String { id }
}
