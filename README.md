# grpc-health-probe-swift

This is a Swift implementation of [grpc_health_probe](https://github.com/grpc-ecosystem/grpc-health-probe). You should probably just use that instead.

> The `grpc_health_probe` utility allows you to query health of gRPC services that
> expose service their status through the [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md).
> 
> `grpc_health_probe` is meant to be used for health checking gRPC applications in
> [Kubernetes](https://kubernetes.io/blog/2018/10/01/health-checking-grpc-servers-on-kubernetes), using the [exec probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/#define-a-liveness-command).

Usage:
`./grpc-health-probe localhost:50000 --connection-timeout 5`
