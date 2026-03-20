# Remove o Dashboard App/Script injetado pelo antigo kanban-backend (astraonline).
# Executa no startup e limpa qualquer referência ao kanban externo.
Rails.application.config.after_initialize do
  Thread.new do
    sleep 25
    begin
      removed = 0

      # 1. Dashboard Apps apontando para o domínio do kanban (busca ampla)
      if defined?(DashboardApp)
        all_apps = DashboardApp.all
        Rails.logger.info "[RemoveKanban] Total DashboardApps no BD: #{all_apps.count}"
        all_apps.each do |app|
          Rails.logger.info "[RemoveKanban] DashboardApp id=#{app.id} name=#{app.name.inspect} content_preview=#{app.content.to_s.first(120).inspect}"
        end

        kanban_apps = DashboardApp.where(
          "content LIKE '%kanban%' OR content LIKE '%moveisback%' OR name LIKE '%kanban%'"
        )
        count = kanban_apps.destroy_all.size
        removed += count
        Rails.logger.info "[RemoveKanban] DashboardApps removidos: #{count}"
      end

      # 2. InstallationConfig com script do kanban (dashboard_script global)
      if defined?(InstallationConfig)
        all_configs = InstallationConfig.where("name LIKE '%script%' OR name LIKE '%dashboard%'")
        Rails.logger.info "[RemoveKanban] InstallationConfigs relevantes: #{all_configs.map { |c| "#{c.name}=#{c.value.to_s.first(80)}" }.inspect}"

        all_configs.each do |cfg|
          next unless cfg.value.to_s =~ /kanban|moveisback\.com\.br/i
          cfg.update!(value: '')
          removed += 1
          Rails.logger.info "[RemoveKanban] InstallationConfig '#{cfg.name}' limpo"
        end
      end

      Rails.logger.info "[RemoveKanban] Limpeza concluída. Total removido/limpo: #{removed}"
    rescue => e
      Rails.logger.warn "[RemoveKanban] Erro na limpeza: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end
  end
end
