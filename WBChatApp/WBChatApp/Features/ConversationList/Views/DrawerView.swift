//
//  DrawerView.swift
//  WBChatApp
//

import SwiftData
import SwiftUI

/// 抽屉：搜索框 + 按时间分组的会话列表 + 底部个人栏
struct DrawerView: View {

    let chatViewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.isDrawerInteracting) private var isDrawerInteracting
    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @State private var viewModel = ConversationListViewModel()
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var deletingConversation: Conversation?

    private var store: ChatStore { ChatStore(context: modelContext) }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if conversations.isEmpty {
                emptyPlaceholder
            } else {
                conversationList
            }

            Divider()
            profileFooter
        }
        .alert("重命名对话", isPresented: isRenamePresented) {
            TextField("对话标题", text: $renameText)
            Button("取消", role: .cancel) { renamingConversation = nil }
            Button("确定") {
                if let conversation = renamingConversation {
                    store.rename(conversation, to: renameText)
                }
                renamingConversation = nil
            }
        }
        .confirmationDialog(
            "删除后无法恢复，确定删除该对话？",
            isPresented: isDeletePresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let conversation = deletingConversation {
                    if chatViewModel.conversation?.id == conversation.id {
                        chatViewModel.startNewConversation()
                    }
                    store.delete(conversation)
                }
                deletingConversation = nil
            }
            Button("取消", role: .cancel) { deletingConversation = nil }
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索对话内容…", text: $viewModel.searchText)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                ForEach(viewModel.sections(from: conversations)) { section in
                    Text(section.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(section.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        // 横向拖抽屉期间禁用列表滚动，与手势方向锁配合，保证只响应一个方向
        .scrollDisabled(isDrawerInteracting)
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let isSelected = chatViewModel.conversation?.id == conversation.id
        return Button {
            chatViewModel.open(conversation)
            router.closeDrawer()
        } label: {
            Text(conversation.title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    isSelected ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .contextMenu {
            Button {
                renameText = conversation.title
                renamingConversation = conversation
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingConversation = conversation
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(viewModel.searchText.isEmpty ? "还没有对话" : "没有匹配的对话")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var profileFooter: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("文")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            Text("我的")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                router.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Bindings

    private var isRenamePresented: Binding<Bool> {
        Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )
    }

    private var isDeletePresented: Binding<Bool> {
        Binding(
            get: { deletingConversation != nil },
            set: { if !$0 { deletingConversation = nil } }
        )
    }
}
