FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod main.go main_test.go ./
RUN go test ./...
ARG REVISION=local
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.revision=${REVISION}" -o /out/api .

FROM scratch
ARG REVISION=local
LABEL org.opencontainers.image.source="https://github.com/grafana-sdlc/sdlc-demo-api" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.description="Sample API for the SDLC deployment and provenance demo"
COPY --from=build /out/api /api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/api"]
