FROM golang:1.10 as build
RUN mkdir -p /go/src/gcsproxy && curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
ADD *.go Gopkg.* /go/src/gcsproxy/
RUN cd /go/src/gcsproxy && dep ensure -v -vendor-only && CGO_ENABLED=0 go build -o /gcsproxy *.go

FROM alpine:3.18
RUN apk --no-cache ca-certificates && update-ca-certificates
CMD ["/gcsproxy"]
COPY --from=build /gcsproxy /gcsproxy
