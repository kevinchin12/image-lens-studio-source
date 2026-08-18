import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensProviders

final class GeminiProviderClientTests: XCTestCase {
    func testFilesUploadURLPreservesCustomBasePathPrefix() {
        let configuration = GeminiProviderConfiguration(
            baseURL: URL(string: "https://proxy.example.test/gemini/v1beta")!
        )

        XCTAssertEqual(
            configuration.filesUploadURL.absoluteString,
            "https://proxy.example.test/gemini/upload/v1beta/files"
        )
    }

    func testAnalysisUsesHeaderAndStrictlyDecodesContract() async throws {
        let json = Self.validAnalysisJSON
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": json]]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!,
                analysisModel: "analysis-model",
                generationModel: "image-model",
                includeChinese: false
            ),
            transport: transport
        )

        let result = try await client.analyze(
            image: ProviderImageInput(data: Data([1, 2, 3]), mimeType: "image/png"),
            apiKey: "secret"
        )

        XCTAssertEqual(result.title, "Test image")
        let recordedRequest = await transport.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
        XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query)
        XCTAssertTrue(request.url!.absoluteString.contains("analysis-model:generateContent"))
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try XCTUnwrap(object["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        XCTAssertNil(generationConfig["temperature"])
    }

    func testGenerationDecodesAllInlineImages() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [
                ["inlineData": ["mimeType": "image/png", "data": Data([4, 5]).base64EncodedString()]],
                ["text": "done"]
            ]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!,
                analysisModel: "analysis-model",
                generationModel: "image-model"
            ),
            transport: transport
        )

        let images = try await client.generate(prompt: "A red cube", aspectRatio: "16:9", apiKey: "secret")

        XCTAssertEqual(images, [GeneratedImagePayload(data: Data([4, 5]), mimeType: "image/png")])
        let recordedRequest = await transport.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try XCTUnwrap(object["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseModalities"] as? [String], ["IMAGE"])
        XCTAssertEqual((generationConfig["imageConfig"] as? [String: String])?["aspectRatio"], "16:9")
    }

    func testGenerationDescribesSeveralRolesForOneReferenceImageWithoutDuplicatingIt() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [
                ["inlineData": ["mimeType": "image/png", "data": Data([9]).base64EncodedString()]]
            ]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!,
                generationModel: "image-model"
            ),
            transport: transport
        )

        _ = try await client.generate(
            prompt: "A product image",
            referenceImages: [
                ProviderImageInput(
                    data: Data([1, 2, 3]),
                    mimeType: "image/png",
                    referenceRoles: [.identity, .palette]
                )
            ],
            aspectRatio: "1:1",
            apiKey: "secret"
        )

        let capturedRequest = await transport.recordedRequest()
        let recordedRequest = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(recordedRequest.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(object["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let texts = parts.compactMap { $0["text"] as? String }
        let inlineImages = parts.compactMap { $0["inlineData"] as? [String: Any] }

        XCTAssertEqual(inlineImages.count, 1)
        XCTAssertTrue(texts.contains { $0.contains("主体与外观") && $0.contains("色彩与配色") })
    }

    func testGenerationUploadsVideoReferenceAndUsesFileData() async throws {
        let uploadSessionURL = URL(string: "https://upload.example.test/session/1")!
        let generatedResponse = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [
                ["inlineData": ["mimeType": "image/png", "data": Data([9]).base64EncodedString()]]
            ]]]]
        ])
        let transport = ScriptedTransport(responses: [
            .init(statusCode: 200, headers: ["X-Goog-Upload-URL": uploadSessionURL.absoluteString]),
            .init(
                statusCode: 200,
                body: try JSONSerialization.data(withJSONObject: [
                    "file": [
                        "name": "files/video-1",
                        "uri": "https://generativelanguage.googleapis.com/v1beta/files/video-1",
                        "mimeType": "video/mp4",
                        "state": "ACTIVE"
                    ]
                ])
            ),
            .init(statusCode: 200, body: generatedResponse),
            .init(statusCode: 200, body: Data("{}".utf8))
        ])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://api.example.test/v1beta")!,
                filesUploadURL: URL(string: "https://api.example.test/upload/v1beta/files")!,
                generationModel: "gemini-3.1-flash-image"
            ),
            transport: transport
        )
        let temporaryVideo = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try Data([0, 1, 2, 3]).write(to: temporaryVideo)
        defer { try? FileManager.default.removeItem(at: temporaryVideo) }

        _ = try await client.generate(
            prompt: "Create a poster inspired by this clip",
            referenceMedia: [
                ProviderMediaInput(
                    source: .managedFile(temporaryVideo),
                    mimeType: "video/mp4",
                    mediaKind: .video,
                    referenceRoles: [.style]
                )
            ],
            aspectRatio: "16:9",
            modelID: "gemini-3.1-flash-image",
            apiKey: "secret"
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST", "POST", "DELETE"])
        XCTAssertEqual(requests[1].url, uploadSessionURL)
        let body = try XCTUnwrap(requests[2].httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(object["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let fileData = try XCTUnwrap(parts.compactMap { $0["fileData"] as? [String: Any] }.first)
        XCTAssertEqual(fileData["mimeType"] as? String, "video/mp4")
        XCTAssertEqual(
            fileData["fileUri"] as? String,
            "https://generativelanguage.googleapis.com/v1beta/files/video-1"
        )
        XCTAssertTrue(parts.compactMap { $0["text"] as? String }.contains { $0.contains("参考视频") })
        let filePartIndex = try XCTUnwrap(parts.firstIndex { $0["fileData"] != nil })
        let finalPromptIndex = try XCTUnwrap(parts.firstIndex { $0["text"] as? String == "Create a poster inspired by this clip" })
        XCTAssertLessThan(filePartIndex, finalPromptIndex)
        XCTAssertTrue(requests[3].url?.path.hasSuffix("/v1beta/files/video-1") == true)
    }

    func testGenerationRequestUsesTheNodeModelInsteadOfTheConfiguredDefault() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [
                ["inlineData": ["mimeType": "image/png", "data": Data([9]).base64EncodedString()]]
            ]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!,
                generationModel: "configured-default"
            ),
            transport: transport
        )
        let request = ImageGenerationRequest(
            target: CompileTarget(
                providerID: ImageGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-3-pro-image"
            ),
            prompt: "A polished product photograph",
            aspectRatio: "1:1"
        )

        _ = try await client.generate(request: request, credential: "secret")

        let capturedRequest = await transport.recordedRequest()
        let recordedRequest = try XCTUnwrap(capturedRequest)
        XCTAssertTrue(recordedRequest.url!.absoluteString.contains("gemini-3-pro-image:generateContent"))
        XCTAssertFalse(recordedRequest.url!.absoluteString.contains("configured-default"))
    }

    func testSemanticMaskEditBetaSendsSourceThenPNGMaskThenExplicitInstruction() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [[
                "inlineData": [
                    "mimeType": "image/png",
                    "data": Data([9]).base64EncodedString()
                ]
            ]]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: transport
        )
        let sourceData = Data([1, 2, 3])
        let maskData = Data([4, 5, 6])
        let request = ImageGenerationRequest(
            target: CompileTarget(
                providerID: ImageGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-3-pro-image"
            ),
            prompt: "Replace the mug with a blue vase",
            editInput: ImageEditInput(
                source: ProviderMediaInput(
                    source: .inline(sourceData),
                    mimeType: "image/jpeg",
                    mediaKind: .image
                ),
                mask: ProviderMediaInput(
                    source: .inline(maskData),
                    mimeType: "image/png",
                    mediaKind: .image
                )
            ),
            aspectRatio: "3:2"
        )

        _ = try await client.generate(request: request, credential: "secret")

        let capturedRequest = await transport.recordedRequest()
        let recordedRequest = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(recordedRequest.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(object["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(
            (parts[0]["inlineData"] as? [String: Any])?["data"] as? String,
            sourceData.base64EncodedString()
        )
        XCTAssertEqual(
            (parts[1]["inlineData"] as? [String: Any])?["data"] as? String,
            maskData.base64EncodedString()
        )
        let instruction = try XCTUnwrap(parts[2]["text"] as? String)
        XCTAssertTrue(instruction.contains("semantic-mask edit beta"))
        XCTAssertTrue(instruction.contains("white marks the requested edit region"))
        XCTAssertTrue(instruction.contains("does not provide a native pixel-locked mask API"))
        XCTAssertEqual(parts[3]["text"] as? String, "Replace the mug with a blue vase")
    }

    func testSemanticMaskEditRejectsNonPNGMaskBeforeSending() async {
        let transport = RecordingTransport(statusCode: 200, responseData: Data())
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(),
            transport: transport
        )
        let request = ImageGenerationRequest(
            target: CompileTarget(
                providerID: ImageGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-3-pro-image"
            ),
            prompt: "Edit the selected area",
            editInput: ImageEditInput(
                source: ProviderMediaInput(
                    source: .inline(Data([1])),
                    mimeType: "image/png",
                    mediaKind: .image
                ),
                mask: ProviderMediaInput(
                    source: .inline(Data([2])),
                    mimeType: "image/jpeg",
                    mediaKind: .image
                )
            ),
            aspectRatio: "1:1"
        )

        do {
            _ = try await client.generate(request: request, credential: "secret")
            XCTFail("Expected non-PNG mask rejection")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(error, .invalidConfiguration("PNG 蒙版"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let capturedRequest = await transport.recordedRequest()
        XCTAssertNil(capturedRequest)
    }

    func testKnownModelRejectsAnUnsupportedAspectRatioBeforeSending() async {
        let transport = RecordingTransport(statusCode: 200, responseData: Data())
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(),
            transport: transport
        )

        do {
            _ = try await client.generate(
                prompt: "test",
                aspectRatio: "1:8",
                modelID: "gemini-3-pro-image",
                apiKey: "secret"
            )
            XCTFail("Expected failure")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(
                error,
                .unsupportedAspectRatio(modelID: "gemini-3-pro-image", aspectRatio: "1:8")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let capturedRequest = await transport.recordedRequest()
        XCTAssertNil(capturedRequest)
    }

    func testProModelRejectsVideoReferenceBeforeUploading() async {
        let transport = RecordingTransport(statusCode: 200, responseData: Data())
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(),
            transport: transport
        )

        do {
            _ = try await client.generate(
                prompt: "test",
                referenceMedia: [
                    ProviderMediaInput(
                        source: .managedFile(URL(fileURLWithPath: "/tmp/reference.mp4")),
                        mimeType: "video/mp4",
                        mediaKind: .video
                    )
                ],
                aspectRatio: "1:1",
                modelID: "gemini-3-pro-image",
                apiKey: "secret"
            )
            XCTFail("Expected failure")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(
                error,
                .unsupportedReferenceMedia(modelID: "gemini-3-pro-image", mediaKind: .video)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let capturedRequest = await transport.recordedRequest()
        XCTAssertNil(capturedRequest)
    }

    func testHTTPErrorIsNormalized() async {
        let data = try! JSONSerialization.data(withJSONObject: ["error": ["message": "bad key"]])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(),
            transport: RecordingTransport(statusCode: 401, responseData: data)
        )

        do {
            _ = try await client.generate(prompt: "test", aspectRatio: "1:1", apiKey: "wrong")
            XCTFail("Expected failure")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(error, .httpFailure(statusCode: 401, message: "bad key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOmniVideoGenerationUsesInteractionsAndDecodesRESTSteps() async throws {
        let videoData = Data([0, 1, 2, 3, 4])
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "steps": [
                ["type": "user_input", "content": [["type": "text", "text": "prompt"]]],
                ["type": "model_output", "content": [[
                    "type": "video",
                    "mime_type": "video/mp4",
                    "data": videoData.base64EncodedString()
                ]]]
            ],
            "status": "completed"
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: transport
        )
        let request = VideoGenerationRequest(
            target: CompileTarget(
                providerID: VideoGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-omni-flash-preview"
            ),
            prompt: "A paper airplane crosses the studio",
            aspectRatio: "16:9"
        )

        let videos = try await client.generate(request: request, credential: "secret")

        XCTAssertEqual(videos, [GeneratedVideoPayload(data: videoData, mimeType: "video/mp4")])
        let capturedRequest = await transport.recordedRequest()
        let recordedRequest = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recordedRequest.httpMethod, "POST")
        XCTAssertEqual(recordedRequest.url?.absoluteString, "https://example.test/v1beta/interactions")
        XCTAssertEqual(recordedRequest.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
        let body = try XCTUnwrap(recordedRequest.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "gemini-omni-flash-preview")
        XCTAssertEqual(object["input"] as? String, "A paper airplane crosses the studio")
        XCTAssertEqual(
            (object["response_format"] as? [String: String]),
            [
                "type": "video",
                "aspect_ratio": "16:9",
                "delivery": "inline",
                "duration": "10s"
            ]
        )
    }

    func testOmniVideoGenerationToleratesPolymorphicStepsWithoutContent() async throws {
        let videoData = Data([7, 8, 9])
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "steps": [
                ["type": "thought", "signature": "thought-signature"],
                ["type": "model_output", "content": [[
                    "type": "video",
                    "mime_type": "video/mp4",
                    "data": videoData.base64EncodedString()
                ]]]
            ]
        ])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: RecordingTransport(statusCode: 200, responseData: responseBody)
        )

        let videos = try await client.generate(
            request: VideoGenerationRequest(
                target: CompileTarget(
                    providerID: VideoGenerationModelCatalog.geminiProviderID,
                    modelID: "gemini-omni-flash-preview"
                ),
                prompt: "A slow cinematic orbit",
                aspectRatio: "16:9"
            ),
            credential: "secret"
        )

        XCTAssertEqual(videos, [GeneratedVideoPayload(data: videoData, mimeType: "video/mp4")])
    }

    func testOmniVideoGenerationSupportsTopLevelOutputVideoFallback() async throws {
        let videoData = Data([3, 2, 1])
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output_video": [
                "type": "video",
                "mime_type": "video/mp4",
                "data": videoData.base64EncodedString()
            ]
        ])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: RecordingTransport(statusCode: 200, responseData: responseBody)
        )

        let videos = try await client.generate(
            request: VideoGenerationRequest(
                target: CompileTarget(
                    providerID: VideoGenerationModelCatalog.geminiProviderID,
                    modelID: "gemini-omni-flash-preview"
                ),
                prompt: "A slow cinematic orbit",
                aspectRatio: "16:9"
            ),
            credential: "secret"
        )

        XCTAssertEqual(videos, [GeneratedVideoPayload(data: videoData, mimeType: "video/mp4")])
    }

    func testOmniVideoGenerationSurfacesModelOutputError() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "status": "failed",
            "steps": [[
                "type": "model_output",
                "error": ["code": 13, "message": "Video generation was rejected"]
            ]]
        ])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: RecordingTransport(statusCode: 200, responseData: responseBody)
        )

        do {
            _ = try await client.generate(
                request: VideoGenerationRequest(
                    target: CompileTarget(
                        providerID: VideoGenerationModelCatalog.geminiProviderID,
                        modelID: "gemini-omni-flash-preview"
                    ),
                    prompt: "A slow cinematic orbit",
                    aspectRatio: "16:9"
                ),
                credential: "secret"
            )
            XCTFail("Expected model-output failure")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(error, .videoGenerationFailed("Video generation was rejected"))
        }
    }

    func testOmniVideoGenerationSurfacesPendingStatusInsteadOfNoVideo() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "id": "interaction-pending",
            "status": "in_progress"
        ])
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: RecordingTransport(statusCode: 200, responseData: responseBody)
        )

        do {
            _ = try await client.generate(
                request: VideoGenerationRequest(
                    target: CompileTarget(
                        providerID: VideoGenerationModelCatalog.geminiProviderID,
                        modelID: "gemini-omni-flash-preview"
                    ),
                    prompt: "A slow cinematic orbit",
                    aspectRatio: "16:9"
                ),
                credential: "secret"
            )
            XCTFail("Expected pending response to be surfaced")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(
                error,
                .videoGenerationFailed("请求尚未完成（状态：in_progress），请稍后重试。")
            )
        }
    }

    func testOmniVideoGenerationEncodesInlineImageReferencesBeforePrompt() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "steps": [["type": "model_output", "content": [[
                "type": "video",
                "mime_type": "video/mp4",
                "data": Data([9]).base64EncodedString()
            ]]]]
        ])
        let transport = RecordingTransport(statusCode: 200, responseData: responseBody)
        let client = GeminiProviderClient(
            configuration: GeminiProviderConfiguration(
                baseURL: URL(string: "https://example.test/v1beta")!
            ),
            transport: transport
        )
        let imageData = Data([4, 5, 6])
        let request = VideoGenerationRequest(
            target: CompileTarget(
                providerID: VideoGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-omni-flash-preview"
            ),
            prompt: "Bring this character to life",
            referenceMedia: [
                ProviderMediaInput(
                    source: .inline(imageData),
                    mimeType: "image/png",
                    mediaKind: .image,
                    referenceRoles: [.identity]
                )
            ],
            aspectRatio: "9:16"
        )

        _ = try await client.generate(request: request, credential: "secret")

        let capturedRequest = await transport.recordedRequest()
        let recordedRequest = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(recordedRequest.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "image")
        XCTAssertEqual(input[0]["mime_type"] as? String, "image/png")
        XCTAssertEqual(input[0]["data"] as? String, imageData.base64EncodedString())
        XCTAssertEqual(input[1]["type"] as? String, "text")
        XCTAssertEqual(input[1]["text"] as? String, "Bring this character to life")
    }

    func testOmniVideoGenerationRejectsVideoReferenceBeforeSending() async {
        let transport = RecordingTransport(statusCode: 200, responseData: Data())
        let client = GeminiProviderClient(configuration: GeminiProviderConfiguration(), transport: transport)
        let request = VideoGenerationRequest(
            target: CompileTarget(
                providerID: VideoGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-omni-flash-preview"
            ),
            prompt: "Edit this clip",
            referenceMedia: [
                ProviderMediaInput(
                    source: .managedFile(URL(fileURLWithPath: "/tmp/reference.mp4")),
                    mimeType: "video/mp4",
                    mediaKind: .video
                )
            ],
            aspectRatio: "16:9"
        )

        do {
            _ = try await client.generate(request: request, credential: "secret")
            XCTFail("Expected video references to be rejected")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(
                error,
                .unsupportedReferenceMedia(
                    modelID: "gemini-omni-flash-preview",
                    mediaKind: .video
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let capturedRequest = await transport.recordedRequest()
        XCTAssertNil(capturedRequest)
    }

    func testOmniVideoGenerationRejectsUnsupportedAspectRatioBeforeSending() async {
        let transport = RecordingTransport(statusCode: 200, responseData: Data())
        let client = GeminiProviderClient(configuration: GeminiProviderConfiguration(), transport: transport)
        let request = VideoGenerationRequest(
            target: CompileTarget(
                providerID: VideoGenerationModelCatalog.geminiProviderID,
                modelID: "gemini-omni-flash-preview"
            ),
            prompt: "A wide landscape",
            aspectRatio: "1:1"
        )

        do {
            _ = try await client.generate(request: request, credential: "secret")
            XCTFail("Expected unsupported aspect ratio")
        } catch let error as GeminiProviderError {
            XCTAssertEqual(
                error,
                .unsupportedVideoAspectRatio(
                    modelID: "gemini-omni-flash-preview",
                    aspectRatio: "1:1"
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let capturedRequest = await transport.recordedRequest()
        XCTAssertNil(capturedRequest)
    }

    func testOmniCatalogExposesOfficialPreviewModelCapabilities() {
        let model = VideoGenerationModelCatalog.geminiOmniFlash

        XCTAssertEqual(model.modelID, "gemini-omni-flash-preview")
        XCTAssertEqual(model.supportedAspectRatios, ["16:9", "9:16"])
        XCTAssertEqual(model.supportedReferenceMediaKinds, [.image])
        XCTAssertEqual(model.lifecycle, .preview)
    }

    private static let validAnalysisJSON = #"{"schemaVersion":"image-lens.reverse-prompt.v1","title":"Test image","modules":{"subject":{"promptEnglish":"red cube","promptChinese":"","evidence":[{"kind":"observable","statement":"a red cube is visible"}]},"style":{"promptEnglish":"","promptChinese":"","evidence":[]},"lighting":{"promptEnglish":"","promptChinese":"","evidence":[]},"camera":{"promptEnglish":"","promptChinese":"","evidence":[]},"environment":{"promptEnglish":"","promptChinese":"","evidence":[]},"material":{"promptEnglish":"","promptChinese":"","evidence":[]},"composition":{"promptEnglish":"","promptChinese":"","evidence":[]},"rendering":{"promptEnglish":"","promptChinese":"","evidence":[]}},"keywords":{"english":["red","cube","object","simple","isolated","geometric"],"chinese":[]}}"#
}

private actor RecordingTransport: ProviderHTTPTransport {
    let statusCode: Int
    let responseData: Data
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int, responseData: Data) {
        self.statusCode = statusCode
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseData, response)
    }

    func recordedRequest() -> URLRequest? {
        lastRequest
    }
}

private actor ScriptedTransport: ProviderHTTPTransport {
    struct Response {
        var statusCode: Int
        var body: Data
        var headers: [String: String]

        init(statusCode: Int, body: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let scripted = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: scripted.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: scripted.headers
        )!
        return (scripted.body, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
