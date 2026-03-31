# Dockerfile customizado para Chatwoot
FROM ghcr.io/fazer-ai/chatwoot:latest

# Metadata
LABEL maintainer="seu-email@exemplo.com"
LABEL description="Chatwoot customizado - Abas All/Unassigned ocultas para agentes"

# ==========================================
# CUSTOMIZAÇÕES DO FRONTEND
# ==========================================

# Copiar componente ChatList.vue modificado
# Oculta abas "All" e "Unassigned" para usuários não-administradores
# (respeita o toggle agent_see_all_conversations definido no Super Admin)
COPY ./custom/ChatList.vue /app/app/javascript/dashboard/components/ChatList.vue

# HTML principal da SPA — injeta script de tema dinâmico por conta
COPY ./custom/vueapp.html.erb /app/app/views/layouts/vueapp.html.erb

# ==========================================
# CUSTOMIZAÇÕES DO BACKEND
# ==========================================

# Inicializador: adiciona campo "Agentes veem todas as conversas" no Super Admin
# e aplica patches no AccountDashboard (Administrate) sem migrações
COPY ./custom/account_dashboard_patch.rb /app/config/initializers/account_dashboard_patch.rb

# Serviço de filtro de permissões de conversas
# Respeita o toggle agent_see_all_conversations configurado no Super Admin
COPY ./custom/permission_filter_service.rb /app/app/services/conversations/permission_filter_service.rb

# Inicializador: tema dinâmico de cores por conta
# Define AccountThemeController + rota GET /account_theme/:account_id
COPY ./custom/account_theme_initializer.rb /app/config/initializers/account_theme_initializer.rb

# Inicializador: desbloqueia features premium no Super Admin
# Seta INSTALLATION_PRICING_PLAN=enterprise para habilitar:
# Custom Branding, Agent Capacity, Audit Logs, Disable Branding
COPY ./custom/enterprise_unlock.rb /app/config/initializers/enterprise_unlock.rb

# Expõe agent_see_all_conversations na API para o frontend respeitar o filtro
COPY ./custom/_account.json.jbuilder /app/app/views/api/v1/models/_account.json.jbuilder

# ==========================================
# CUSTOMIZAÇÕES ADICIONAIS (OPCIONAL)
# ==========================================

# Atualizar sistema e instalar pacotes adicionais (se necessário)
# RUN apt-get update && apt-get install -y \
#     vim \
#     curl \
#     && rm -rf /var/lib/apt/lists/*

# Copiar outros arquivos de configuração customizados
# COPY ./config/custom-config.yml /app/config/

# Variáveis de ambiente personalizadas
# ENV RAILS_ENV=production
# ENV NODE_ENV=production
# ENV CUSTOM_FEATURE_FLAG=true

# Expor portas (já expostas na imagem base, mas você pode adicionar outras)
# EXPOSE 3000

# Criar diretórios adicionais se necessário
# RUN mkdir -p /app/custom_data

# Copiar scripts customizados
# COPY ./scripts /app/scripts
# RUN chmod +x /app/scripts/*.sh

# Healthcheck customizado (opcional)
# HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
#   CMD curl -f http://localhost:3000/health || exit 1

# Comando de inicialização (usar o padrão da imagem base)
# CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
