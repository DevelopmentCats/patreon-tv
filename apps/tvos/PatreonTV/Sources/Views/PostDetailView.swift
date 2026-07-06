//
//  PostDetailView.swift
//  PatreonTV
//
//  Full detail for a single post. Fetches by ID (which returns the media
//  relationship with the Mux HLS URL if the current session can view it).
//

import SwiftUI

struct PostDetailView: View {

    let postID: String

    @State private var post: Post?
    @State private var mediaURL: URL?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showPlayer = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.large)
            } else if let post {
                loaded(post: post)
            } else if let errorMessage {
                ErrorView(message: errorMessage) { Task { await load() } }
            }
        }
        .task { await load() }
        .background(PatreonColors.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPlayer) {
            if let mediaURL {
                PlayerView(mediaURL: mediaURL, title: post?.attributes.title ?? "")
            }
        }
    }

    @ViewBuilder
    private func loaded(post: Post) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                Text(post.attributes.title ?? "Untitled")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(PatreonColors.primaryText)
                    .padding(.horizontal, 60)
                    .padding(.top, 60)

                if let mediaURL {
                    Button {
                        showPlayer = true
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 48)
                            .padding(.vertical, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PatreonColors.brand)
                    .padding(.horizontal, 60)
                } else if post.attributes.currentUserCanView == false {
                    lockedNotice
                }

                if let teaser = post.attributes.teaser, !teaser.isEmpty {
                    Text(teaser)
                        .font(.title3)
                        .foregroundStyle(PatreonColors.secondaryText)
                        .padding(.horizontal, 60)
                }

                if let content = post.attributes.content, !content.isEmpty {
                    // Content is HTML — for MVP we strip tags and show plaintext.
                    Text(stripHTML(content))
                        .font(.body)
                        .foregroundStyle(PatreonColors.primaryText.opacity(0.9))
                        .padding(.horizontal, 60)
                }

                Spacer(minLength: 60)
            }
        }
    }

    private var lockedNotice: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill")
            Text("This post is only available to patrons at a higher tier.")
        }
        .font(.title3)
        .foregroundStyle(PatreonColors.secondaryText)
        .padding(.horizontal, 60)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let doc = try await PatreonClient.shared.post(id: postID)
            self.post = doc.data
            self.mediaURL = extractMediaURL(from: doc)
        } catch {
            errorMessage = (error as? PatreonError)?.errorDescription
                ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Walk the `included` array for a media resource whose display.url is set.
    /// This is where the signed Mux HLS URL lives when the current session
    /// is entitled to view the post.
    private func extractMediaURL(from doc: SingleResource<Post>) -> URL? {
        for inc in doc.included ?? [] {
            if case .media(let media) = inc {
                if let url = media.attributes.display?.url {
                    return url
                }
                // Fall back to download_url if display.url isn't set but
                // download_url is (rare for video, common for audio/images).
                if let url = media.attributes.downloadURL,
                   media.attributes.mimetype?.hasPrefix("video/") == true
                        || media.attributes.mimetype == "application/x-mpegURL" {
                    return url
                }
            }
        }
        return nil
    }

    private func stripHTML(_ html: String) -> String {
        // Trivially unescape and remove tags. For MVP we render plaintext;
        // later we'll render HTML with a proper renderer.
        var s = html
        s = s.replacingOccurrences(of: "<br>", with: "\n")
        s = s.replacingOccurrences(of: "</p>", with: "\n\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
