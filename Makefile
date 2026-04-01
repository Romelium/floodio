.PHONY: generate run

generate:
	mkdir -p lib/protos
	protoc --dart_out=lib/protos -Iprotos protos/models.proto
	dart run build_runner build --delete-conflicting-outputs

run:
	flutter run --dart-define-from-file=.env
