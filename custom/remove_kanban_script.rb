# Remove o Dashboard App/Script injetado pelo antigo kanban-backend (astraonline).
# Executa uma única vez no startup e se auto-desativa após a limpeza.
Rails.application.config.after_initialize do
  Thread.new do
    sleep 25
    begin
      removed = 0

      # 1. Dashboard Apps apontando para o domínio do kanban
      if defined?(DashboardApp)
        count = DashboardApp
          .where("content LIKE '%kanban.moveisback.com.br%' OR content LIKE '%kanbanback%' OR content LIKE '%kanbanfront%'")
          .destroy_all
          .size
        removed += count
        Rails.logger.info "[RemoveKanban] DashboardApp removidos: #{count}" if count > 0
      end

      # 2. InstallationConfig com script do kanban (dashboard_script global)
      if defined?(InstallationConfig)
        %w[dashboard_script DASHBOARD_SCRIPT].each do |key|
          cfg = InstallationConfig.find_by(name: key)
          next unless cfg&.value.to_s.include?('kanban')
          cfg.update!(value: '')
          removed += 1
          Rails.logger.info "[RemoveKanban] InstallationConfig '#{key}' limpo"
        end
      end

      Rails.logger.info "[RemoveKanban] Limpeza concluída. Total removido: #{removed}" if removed > 0
    rescue => e
      Rails.logger.warn "[RemoveKanban] Erro na limpeza: #{e.message}"
    end
  end
end
