# Remove DashboardApps e scripts indesejados do BD.
# - Kanban externo (astraonline)
# - Apps legados do fazer-ai que não são usados (Conexões, Chats Internos, Projetos, Chatbot Flows, Config Extra)
Rails.application.config.after_initialize do
  Thread.new do
    sleep 25
    begin
      removed = 0

      if defined?(DashboardApp)
        all_apps = DashboardApp.all
        Rails.logger.info "[CleanApps] Total DashboardApps no BD: #{all_apps.count}"
        all_apps.each do |app|
          Rails.logger.info "[CleanApps] id=#{app.id} name=#{app.name.inspect} content=#{app.content.to_s.first(80).inspect}"
        end

        # Remove apps indesejados pelo nome (kanban + apps fazer-ai não utilizados)
        unwanted_names = [
          'kanban', 'Conexões', 'Conexoes', 'Chats Internos',
          'Projetos', 'Chatbot Flows', 'Config Extra'
        ]
        unwanted_pattern = unwanted_names.map { |n| DashboardApp.sanitize_sql_like(n) }.join('|')

        apps_to_remove = all_apps.select do |app|
          unwanted_names.any? { |name| app.name.to_s.downcase.include?(name.downcase) } ||
            app.content.to_s =~ /kanban|moveisback\.com\.br/i
        end

        apps_to_remove.each do |app|
          app.destroy!
          removed += 1
          Rails.logger.info "[CleanApps] Removido: id=#{app.id} name=#{app.name.inspect}"
        end

        Rails.logger.info "[CleanApps] DashboardApps removidos: #{removed}"
      end

      # InstallationConfig com script do kanban
      if defined?(InstallationConfig)
        all_configs = InstallationConfig.where("name LIKE '%script%' OR name LIKE '%dashboard%'")
        all_configs.each do |cfg|
          next unless cfg.value.to_s =~ /kanban|moveisback\.com\.br/i
          cfg.update!(value: '')
          removed += 1
          Rails.logger.info "[CleanApps] InstallationConfig '#{cfg.name}' limpo"
        end
      end

      Rails.logger.info "[CleanApps] Limpeza concluída. Total removido/limpo: #{removed}"
    rescue => e
      Rails.logger.warn "[CleanApps] Erro na limpeza: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end
  end
end
