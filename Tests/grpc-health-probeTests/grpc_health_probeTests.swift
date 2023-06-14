
import ArgumentParser
import XCTest
@testable import grpc_health_probe

final class grpc_health_probeTests: XCTestCase {

    
    func testValidate() {
        var probe = GRPCHealthProbe()
        
        // Negative cases
        probe.address = ""
        XCTAssertThrowsError(try probe.validate(), "address not specified")
        
        probe.address = "localhost:50051"
        probe.rpcHeaders = ["invalidHeader"]
        XCTAssertThrowsError(try probe.validate(), "invalid RPC header")
        
        probe.rpcHeaders = ["valid:header"]
        probe.connectionTimeout = 0
        XCTAssertThrowsError(try probe.validate(), "--timeout must be greater than zero")

        probe.connectionTimeout = 1
        probe.rpcTimeout = 0
        XCTAssertThrowsError(try probe.validate(), "--rpc-timeout must be greater than zero")
        
        probe.rpcTimeout = 1
        probe.tls = false
        probe.tlsNoVerify = true
        XCTAssertThrowsError(try probe.validate(), "specified --tls-no-verify without specifying --tls")
        
        probe.tlsNoVerify = false
        probe.tlsCACert = "cert.pem"
        XCTAssertThrowsError(try probe.validate(), "specified --tls-ca-cert without specifying --tls")
    }
    
    func testInvalidArguments() async throws {
        var probe = GRPCHealthProbe()
        probe.address = ""

        do {
            try await probe.run()
        } catch let error as ExitCode {
            XCTAssert(error == .init(GRPCHealthProbe.Status.invalidArguments.rawValue))
        }

        probe.address = "localhost:50051"
        probe.rpcHeaders = ["invalidHeader"]
        do {
            try await probe.run()
        } catch let error as ExitCode {
            XCTAssert(error == .init(GRPCHealthProbe.Status.invalidArguments.rawValue))
        }
    }
}
