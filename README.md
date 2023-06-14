# grpc-health-probe-swift

This is a Swift implementation of [grpc_health_probe](https://github.com/grpc-ecosystem/grpc-health-probe). You should probably just use that instead.

> The `grpc_health_probe` utility allows you to query health of gRPC services that
> expose service their status through the [gRPC Health Checking Protocol][hc].
> 
> `grpc_health_probe` is meant to be used for health checking gRPC applications in
> [Kubernetes][k8s], using the [exec probes][execprobe].

Usage:
`./grpc-health-probe localhost:50000 --connection-timeout 5`