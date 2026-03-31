# Cria automaticamente o inbox "Chat Interno" para cada conta ao iniciar o servidor.
# Isso garante que o recurso de chat interno entre agentes funcione sem configuração manual.
Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    begin
      # Busca apenas contas que ainda não têm o inbox — evita N+1 queries
      accounts_without_inbox = Account.where.not(
        id: Inbox.select(:account_id).where(name: 'Chat Interno')
      )

      accounts_without_inbox.find_each do |account|
        channel = Channel::Api.create!(account: account, webhook_url: '')
        account.inboxes.create!(name: 'Chat Interno', channel: channel)
        Rails.logger.info "[InternalChat] Inbox 'Chat Interno' criado para account #{account.id}"
      rescue StandardError => e
        Rails.logger.warn "[InternalChat] Skipped account #{account.id}: #{e.message}"
      end
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      retries += 1
      sleep 5
      retry if retries < 6
    rescue StandardError => e
      Rails.logger.warn "[InternalChat] Setup falhou: #{e.message}"
    end
  end
end
