
import ArgumentParser
import Foundation.NSDate
import GRPC
import Logging
import NIOHPACK
import NIOPosix
import NIOSSL
import NIOTLS

@main
struct GRPCHealthProbe: AsyncParsableCommand {

    @Argument(help: "tcp host:port to connect")
    var address: String
    
    @Option(help: "service name to check")
    var service: String = ""
    
    @Option(help: "user-agent header value of health check requests")
    var userAgent: String = "grpc_health_probe"

    @Option(help: "timeout for establishing connection (seconds)")
    var connectionTimeout: Int64 = 1
    
    @Option(help: "additional RPC headers in 'name: value' format")
    var rpcHeaders: [String] = []
    
    @Option(help: "timeout for health check rpc (seconds)")
    var rpcTimeout: Int64 = 1
    
    @Flag(help: "use TLS (default: false, INSECURE plaintext transport)")
    var tls: Bool = false
    
    @Flag(help: "with --tls) don't verify the certificate (INSECURE) presented by the server")
    var tlsNoVerify: Bool = false
    
    @Option(help: "(with --tls, optional) file containing trusted certificates for verifying server")
    var tlsCACert: String?
    
    @Option(help: "(with --tls, optional) client certificate for authenticating to the server (requires --tls-client-key)")
    var tlsClientCert: String?

    @Option(help: "(with --tls) client private key for authenticating to the server (requires --tls-client-cert)")
    var tlsClientKey: String?
    
    @Option(help: "(with --tls) override the hostname used to verify the server certificate")
    var tlsServerName: String?
    
    @Flag(help: "use GZIPCompressor for requests and GZIPDecompressor for response")
    var gzip: Bool = false
    
    @Flag(help: "verbose logs")
    var verbose: Bool = false
    
    enum Status: Int32 {
        case serving = 0
        // StatusInvalidArguments indicates specified invalid arguments.
        case invalidArguments = 1
        // StatusConnectionFailure indicates connection failed.
        case connectionFailure = 2
        // StatusRPCFailure indicates rpc failed.
        case rpcFailure = 3
        // StatusUnhealthy indicates rpc succeeded but indicates unhealthy service.
        case unhealthy = 4
    }
    
    func buildTLSCredentials() throws -> GRPCTLSConfiguration {
        var certificateChain = [NIOSSLCertificateSource]()
        var privateKey: NIOSSLPrivateKeySource?
        var trustRoots: NIOSSLTrustRoots?
        
        if let tlsClientCert, let tlsClientKey {
            let cert = try NIOSSLCertificate(file: tlsClientCert, format: .pem)
            let key = try NIOSSLPrivateKey(file: tlsClientKey, format: .pem)
            certificateChain = [.certificate(cert)]
            privateKey = .privateKey(key)
        }
        
        if let tlsCACert {
            let caCert = try NIOSSLCertificate(file: tlsCACert, format: .pem)
            trustRoots = .certificates([caCert])
        }
        
        return GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
            certificateChain: certificateChain,
            privateKey: privateKey,
            trustRoots: trustRoots ?? .default,
            certificateVerification: tlsNoVerify ? .none : .fullVerification,
            hostnameOverride: tlsServerName,
            customVerificationCallback: nil
        )
    }
    
    // MARK: - run
    
    public func run() async throws {
        let logger = Logger(label: "com.grpc-health-probe.main")
        
        // parse host
        let split = address.split(separator: ":")
        guard let host = split.first, let portStr = split.last, let port = Int(portStr) else {
            throw ExitCode(Status.invalidArguments.rawValue)
        }
        
        // parse headers
        var headers = HPACKHeaders(
            try rpcHeaders.map {
                let parts = $0.split(separator: ":")
                if parts.count == 2, let key = parts.first, let value = parts.last {
                    return (String(key), String(value))
                } else {
                    throw ExitCode(Status.invalidArguments.rawValue)
                }
            }
        )
        headers.add(contentsOf: [("user-agent", userAgent)])
        
        if verbose {
            logger.log(
                level: .info,
                """
                Parsed options:
                > address: \(address)
                > service: \(service)
                > user-agent: \(userAgent)
                > connection-timeout: \(connectionTimeout)
                > rpc-timeout: \(rpcTimeout)
                > rpcHeaders: \(headers.prettyPrint)
                > tls: \(tls)
                > tls-no-verify: \(tlsNoVerify)
                > tls-ca-cert: \(String(describing: tlsCACert))
                > tls-client-cert: \(String(describing: tlsClientCert))
                > tls-client-key: \(String(describing: tlsClientKey))
                > tls-server-name: \(String(describing: tlsServerName))
                > gzip: \(gzip)
                > verbose: \(verbose)
                """
            )
        }
        
        if verbose {
            logger.log(level: .info, "establishing connection")
        }
        
        // Setup an `EventLoopGroup` for the connection to run on.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Make sure the group is shutdown when we're done with it.
        defer {
            try! group.syncShutdownGracefully()
        }
        
        let connectionStart = Date()
        let channel: GRPCChannel
        do {
            channel = try GRPCChannelPool.with(
                target: .hostAndPort(String(host), port),
                transportSecurity: tls ? .tls(try buildTLSCredentials()) : .plaintext,
                eventLoopGroup: group
            ) { config in
                config.keepalive = ClientConnectionKeepalive(timeout: .seconds(connectionTimeout))
            }
        } catch {
            throw ExitCode(Status.connectionFailure.rawValue)
        }
        // Close the connection when we're done with it.
        defer {
            try! channel.close().wait()
        }
        
        let connectionDuration = Date().timeIntervalSince(connectionStart)
        if verbose {
            logger.log(level: .info, "connection established (took \(connectionDuration)")
        }
        
        let rpcStart = Date()
        var options = CallOptions()
        options.customMetadata = headers
        options.logger = logger
        options.timeLimit = TimeLimit.timeout(.seconds(rpcTimeout))
        if gzip {
            options.messageEncoding = .enabled(.init(forRequests: .gzip, decompressionLimit: .ratio(20)))
        }
        let client = Grpc_Health_V1_HealthAsyncClient(channel: channel, defaultCallOptions: options)
        let req = Grpc_Health_V1_HealthCheckRequest.with {
            $0.service = service
        }
        
        do {
            let response = try await client.check(req)
            let rpcDuration = Date().timeIntervalSince(rpcStart)
            switch response.status {
            case .serving:
                if verbose {
                    logger.log(level: .info, "rpc complete (took \(rpcDuration)")
                }
                logger.log(level: .info, "status: \(response.status)")
                GRPCHealthProbe.exit()
            default:
                logger.log(level: .info, "service unhealthy (responded with \(response.status)")
                throw ExitCode(Status.unhealthy.rawValue)
            }
        } catch let error {
            if let status = error as? GRPCStatus {
                switch status.code {
                case .unimplemented:
                    logger.log(level: .error, "this server does not implement the grpc health protocol (grpc.health.v1.Health)")
                case .deadlineExceeded:
                    logger.log(level: .error, "timeout: health rpc did not complete within \(rpcTimeout)")
                default:
                    break
                }
            }
            
            logger.log(level: .error, "health rpc failed with error: \(error)")
            throw ExitCode(Status.rpcFailure.rawValue)
        }
    }
    
    // MARK: - validate
        
    func validate() throws {
        if address.isEmpty {
            throw ValidationError("address not specified")
        }
        
        for header in rpcHeaders {
            let parts = header.split(separator: ":")
            if parts.count != 2 {
                throw ValidationError("invalid RPC header, expected 'key: value', got \(header)")
            }
        }
        
        if connectionTimeout <= 0 {
            throw ValidationError("--timeout must be greater than zero (specified: \(connectionTimeout)")
        }
        
        if rpcTimeout <= 0 {
            throw ValidationError("--rpc-timeout must be greater than zero (specified: \(rpcTimeout)")
        }
        
        if !tls && tlsNoVerify {
            throw ValidationError("specified --tls-no-verify without specifying --tls")
        }
        
        if let _ = tlsCACert, !tls {
            throw ValidationError("specified --tls-ca-cert without specifying --tls")
        }
        
        if let _ = tlsClientCert, !tls {
            throw ValidationError("specified --tls-client-cert without specifying --tls")
        }
        
        if let _ = tlsServerName, !tls {
            throw ValidationError("specified --tls-server-name without specifying --tls")
        }
        
        if let _ = tlsClientCert, tlsClientKey == nil {
            throw ValidationError("specified --tls-client-cert without specifying --tls-client-key")
        }
        
        if let _ = tlsClientKey, tlsClientCert == nil {
            throw ValidationError("specified --tls-client-key without specifying --tls-client-cert")
        }
        
        if let _ = tlsCACert, tlsNoVerify {
            throw ValidationError("cannot specify --tls-ca-cert with --tls-no-verify (CA cert would not be used)")
        }
        
        if let _ = tlsServerName, tlsNoVerify {
            throw ValidationError("cannot specify --tls-server-name with --tls-no-verify (server name would not be used)")
        }
    }
}

extension HPACKHeaders {
    var prettyPrint: String {
        return "[" + self.map { name, value, _ in
          "'\(name)': '\(value)'"
        }.joined(separator: ", ") + "]"
    }
}
