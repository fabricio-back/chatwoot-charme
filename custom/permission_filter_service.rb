class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    # Quando o Super Admin ativou "Agentes veem todas as conversas" para esta conta
    return conversations if account_allows_agent_see_all?

    accessible_conversations
  end

  private

  def account_allows_agent_see_all?
    (account.custom_attributes || {}).fetch('agent_see_all_conversations', false) == true
  end

  def accessible_conversations
    # Agentes veem conversas onde são assignee OU participante
    participant_conversation_ids = ConversationParticipant
      .where(user_id: user.id)
      .pluck(:conversation_id)

    scope = conversations.where(inbox: user.inboxes.where(account_id: account.id))

    if participant_conversation_ids.present?
      scope.where(assignee_id: user.id)
           .or(scope.where(id: participant_conversation_ids))
    else
      scope.where(assignee_id: user.id)
    end
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
