<script setup>
/**
 * Chat Interno – mensagens diretas entre agentes
 * v2: import axios explícito (Vite não tem global), auth via api_access_token,
 * parsing correto da API v4, optimistic UI, busca de agentes, status online.
 */
import { ref, watch, onUnmounted, nextTick, computed } from 'vue';
import axios from 'axios';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const emit = defineEmits(['close']);

const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

// ---------- State ----------
const agents = ref([]);
const selectedAgent = ref(null);
const messages = ref([]);
const newMessage = ref('');
const inboxId = ref(null);
const conversationId = ref(null);
const loading = ref(false);
const loadingAgents = ref(false);
const sending = ref(false);
const errorMsg = ref('');
const messagesEl = ref(null);
const searchQuery = ref('');
// ID do agente assignee da conversa (quem criou = ó dono)
// Dono envia como 'outgoing' (→ direita), quem responde envia como 'incoming' (→ esquerda)
const conversationAssigneeId = ref(null);
let pollTimer = null;

const INBOX_NAME = 'Chat Interno';

// ---------- Auth helpers ----------
// No Chatwoot v4 com Vite, axios não é global. Usamos import explícito.
// Preferimos api_access_token — evita CSRF. Fallback: CSRF token da sessão Rails.
const getHeaders = (write = false) => {
  const token = currentUser.value?.access_token;
  if (token) return { 'api_access_token': token };
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content ?? '';
  const h = {};
  if (write && csrf) h['X-CSRF-Token'] = csrf;
  return h;
};

const apiGet = (url, params = {}) =>
  axios.get(url, { params, headers: getHeaders(false) });

const apiPost = (url, data = {}) =>
  axios.post(url, data, {
    headers: { ...getHeaders(true), 'Content-Type': 'application/json' },
  });

// ---------- Computed ----------
const filteredAgents = computed(() => {
  const q = searchQuery.value.toLowerCase().trim();
  if (!q) return agents.value;
  return agents.value.filter(
    a => a.name.toLowerCase().includes(q) || (a.email ?? '').toLowerCase().includes(q)
  );
});

// ---------- Utils ----------
const pairKey = (a, b) => [Math.min(a, b), Math.max(a, b)].join('-');
const dmEmail = pair => `internal-dm-${pair}@chatwoot.internal`;
const initial = name => (name ?? '?')[0].toUpperCase();
const avatarBg = id => {
  const p = ['#aa0101','#b45309','#047857','#1d4ed8','#6d28d9','#be185d','#0891b2','#65a30d','#dc2626','#7c3aed'];
  return p[Math.abs(id ?? 0) % p.length];
};
const fmt = ts => {
  if (!ts) return '';
  const d = new Date(ts * 1000);
  const today = new Date().toDateString() === d.toDateString();
  const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  return today ? time : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) + ' ' + time;
};
// Compara como Number para evitar false negativo (string vs number) entre API e store
const isMe = msg => Number(msg.sender?.id) === Number(currentUser.value?.id);
const dotColor = s => ({ online: 'bg-green-400', busy: 'bg-amber-400' })[s] ?? 'bg-gray-400';
const dotLabel = s => ({ online: 'Online', busy: 'Ocupado' })[s] ?? 'Offline';

// Extrai array de qualquer shape da API v4
const extractList = (payload, key) => {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload;
  if (key && Array.isArray(payload[key])) return payload[key];
  if (Array.isArray(payload.payload)) return payload.payload;
  return [];
};

// ---------- API ----------
const loadAgents = async () => {
  loadingAgents.value = true;
  errorMsg.value = '';
  try {
    const res = await apiGet(`/api/v1/accounts/${accountId.value}/agents`);
    const all = Array.isArray(res.data) ? res.data : [];
    const orderMap = { online: 0, busy: 1, offline: 2 };
    agents.value = all
      .filter(a => a.id !== currentUser.value?.id)
      .sort((a, b) => (orderMap[a.availability_status] ?? 2) - (orderMap[b.availability_status] ?? 2));
  } catch (e) {
    const s = e.response?.status;
    errorMsg.value = s === 401 ? 'Sessão expirada — recarregue a página.'
      : s === 403 ? 'Sem permissão para listar agentes.'
      : `Erro ao carregar agentes (${s ?? 'rede'}).`;
  } finally {
    loadingAgents.value = false;
  }
};

const ensureInbox = async () => {
  if (inboxId.value) return;
  const res = await apiGet(`/api/v1/accounts/${accountId.value}/inboxes`);
  const list = extractList(res.data?.payload) || extractList(res.data);
  let inbox = list.find(i => i.name === INBOX_NAME);
  if (!inbox) {
    if (currentUser.value?.role !== 'administrator') {
      throw new Error('O inbox "Chat Interno" não existe. Peça ao administrador que abra o Chat Interno uma vez para criá-lo.');
    }
    const r = await apiPost(`/api/v1/accounts/${accountId.value}/inboxes`, {
      name: INBOX_NAME,
      channel: { type: 'api', webhook_url: '' },
    });
    inbox = r.data?.payload ?? r.data;
  }
  inboxId.value = inbox.id;
};

const ensureContact = async (pair, myName, theirName) => {
  const email = dmEmail(pair);
  try {
    const res = await apiGet(`/api/v1/accounts/${accountId.value}/contacts/search`, {
      q: email,
      include_contacts: true,
    });
    const contacts = extractList(res.data?.payload, 'contacts');
    if (contacts.length && contacts[0]?.id) return contacts[0].id;
  } catch { /* cria novo */ }

  const r = await apiPost(`/api/v1/accounts/${accountId.value}/contacts`, {
    name: `DM: ${myName} vs ${theirName}`,
    email,
    account_id: accountId.value,
  });
  return r.data?.id ?? r.data?.payload?.id;
};

const ensureConversation = async contactId => {
  if (!contactId) throw new Error('Contato interno inválido.');
  const res = await apiGet(`/api/v1/accounts/${accountId.value}/contacts/${contactId}/conversations`);
  const convs = extractList(res.data?.payload) || extractList(res.data);
  const open = convs.find(c => c.inbox_id === inboxId.value && c.status !== 'resolved');
  if (open) {
    // Captura o assignee da conversa existente para determinar direção de mensagens
    conversationAssigneeId.value =
      Number(open.meta?.assignee?.id) ||
      Number(open.assignee_id) ||
      null;
    return open.id;
  }

  const r = await apiPost(`/api/v1/accounts/${accountId.value}/conversations`, {
    inbox_id: inboxId.value,
    contact_id: contactId,
    assignee_id: currentUser.value?.id,
  });
  const convId = r.data?.id ?? r.data?.data?.id ?? r.data?.payload?.id;
  if (!convId) throw new Error('Não foi possível criar a conversa interna.');

  // Quem cria a conversa é o assignee (dono)
  conversationAssigneeId.value = Number(currentUser.value?.id);

  await apiPost(
    `/api/v1/accounts/${accountId.value}/conversations/${convId}/participants`,
    { user_ids: [currentUser.value?.id, selectedAgent.value?.id].filter(Boolean) }
  ).catch(() => {});

  return convId;
};

const loadMessages = async () => {
  if (!conversationId.value) return;
  try {
    const res = await apiGet(
      `/api/v1/accounts/${accountId.value}/conversations/${conversationId.value}/messages`
    );
    const raw = res.data?.payload;
    const all = Array.isArray(raw)
      ? raw
      : Array.isArray(raw?.payload)
        ? raw.payload
        : [];

    const prev = messages.value.length;
    const filtered = all
      .filter(m => m.content && m.message_type !== 2 && m.message_type !== 3)
      .sort((a, b) => a.created_at - b.created_at);
    messages.value = filtered;
    if (filtered.length > prev) scrollBottom();
  } catch { /* ignora erros de polling */ }
};

const sendMessage = async () => {
  const text = newMessage.value.trim();
  if (!text || !conversationId.value || sending.value) return;
  newMessage.value = '';
  sending.value = true;

  // Dono da conversa (assignee) → 'outgoing' (direção: direita)
  // Quem responde → 'incoming' (direção: esquerda na view nativa do Chatwoot)
  // isMe() continua funcionando pois o Chatwoot armazena o User como sender
  // independente do message_type quando enviado via API de agente.
  const amIAssignee =
    conversationAssigneeId.value &&
    Number(conversationAssigneeId.value) === Number(currentUser.value?.id);
  const msgType = amIAssignee ? 'outgoing' : 'incoming';
  const msgTypeNum = amIAssignee ? 1 : 0;

  const tempId = `temp-${Date.now()}`;
  messages.value = [
    ...messages.value,
    {
      id: tempId,
      content: text,
      created_at: Math.floor(Date.now() / 1000),
      sender: { id: currentUser.value?.id, name: currentUser.value?.name },
      message_type: msgTypeNum,
    },
  ];
  scrollBottom();

  try {
    await apiPost(
      `/api/v1/accounts/${accountId.value}/conversations/${conversationId.value}/messages`,
      { content: text, message_type: msgType }
    );
    await loadMessages();
  } catch {
    newMessage.value = text;
    messages.value = messages.value.filter(m => m.id !== tempId);
  } finally {
    sending.value = false;
  }
};

// ---------- Fluxo ----------
const openChat = async agent => {
  selectedAgent.value = agent;
  loading.value = true;
  errorMsg.value = '';
  messages.value = [];
  conversationId.value = null;
  stopPoll();

  try {
    await ensureInbox();
    const pair = pairKey(currentUser.value?.id, agent.id);
    const contactId = await ensureContact(pair, currentUser.value?.name ?? 'Eu', agent.name);
    conversationId.value = await ensureConversation(contactId);
    await loadMessages();
    startPoll();
  } catch (e) {
    errorMsg.value = e.message || 'Erro ao abrir a conversa.';
    selectedAgent.value = null;
  } finally {
    loading.value = false;
  }
};

const backToList = () => {
  stopPoll();
  selectedAgent.value = null;
  messages.value = [];
  conversationId.value = null;
  conversationAssigneeId.value = null;
  errorMsg.value = '';
};

const retryInit = () => { errorMsg.value = ''; loadAgents(); };

// ---------- Poll ----------
const startPoll = () => { stopPoll(); pollTimer = setInterval(loadMessages, 3000); };
const stopPoll = () => { if (pollTimer) { clearInterval(pollTimer); pollTimer = null; } };

// ---------- Scroll ----------
const scrollBottom = () =>
  nextTick(() => { if (messagesEl.value) messagesEl.value.scrollTop = messagesEl.value.scrollHeight; });

// ---------- Lifecycle ----------
watch(() => currentUser.value?.id, id => { if (id) loadAgents(); }, { immediate: true });
onUnmounted(stopPoll);
</script>

<template>
  <!-- CABEÇALHO -->
  <div class="flex items-center gap-2 px-3 py-2.5 border-b border-n-weak flex-shrink-0 min-w-0">
    <button
      v-if="selectedAgent"
      class="flex items-center justify-center size-7 rounded-lg hover:bg-n-alpha-2 transition-colors text-n-slate-11 flex-shrink-0"
      title="Voltar para lista"
      @click="backToList"
    >
      <span class="i-lucide-arrow-left size-4" />
    </button>

    <div
      v-if="selectedAgent"
      class="flex items-center justify-center size-7 rounded-full flex-shrink-0 text-white text-xs font-bold"
      :style="{ backgroundColor: avatarBg(selectedAgent.id) }"
    >
      {{ initial(selectedAgent.name) }}
    </div>

    <div class="flex-1 min-w-0">
      <span class="block font-semibold text-sm text-n-slate-12 truncate leading-tight">
        {{ selectedAgent ? selectedAgent.name : 'Chat Interno' }}
      </span>
      <span v-if="selectedAgent" class="flex items-center gap-1 text-xs text-n-slate-9 leading-tight">
        <span class="inline-block size-1.5 rounded-full" :class="dotColor(selectedAgent.availability_status)" />
        {{ dotLabel(selectedAgent.availability_status) }}
      </span>
    </div>

    <button
      v-if="!selectedAgent"
      class="flex items-center justify-center size-7 rounded-lg hover:bg-n-alpha-2 transition-colors flex-shrink-0"
      title="Atualizar lista"
      @click="loadAgents"
    >
      <span class="i-lucide-refresh-cw size-3.5 text-n-slate-9" :class="{ 'animate-spin': loadingAgents }" />
    </button>

    <button
      class="flex items-center justify-center size-7 rounded-lg hover:bg-n-alpha-2 transition-colors text-n-slate-10 flex-shrink-0"
      title="Fechar chat interno"
      @click="emit('close')"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>

  <!-- BANNER DE ERRO -->
  <div
    v-if="errorMsg"
    class="mx-3 mt-2 p-2.5 rounded-lg bg-red-50 dark:bg-red-950 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-300 text-xs flex gap-2 items-start flex-shrink-0"
  >
    <span class="i-lucide-alert-circle size-4 flex-shrink-0 mt-0.5" />
    <div class="flex-1 min-w-0">
      <p class="leading-snug">{{ errorMsg }}</p>
      <button class="mt-1 text-xs underline hover:no-underline font-medium" @click="retryInit">
        Tentar novamente
      </button>
    </div>
  </div>

  <!-- LISTA DE AGENTES -->
  <template v-if="!selectedAgent">
    <div class="px-3 pt-2 pb-1 flex-shrink-0">
      <div class="relative">
        <span class="absolute left-2.5 top-1/2 -translate-y-1/2 i-lucide-search size-3.5 text-n-slate-9 pointer-events-none" />
        <input
          v-model="searchQuery"
          class="w-full text-xs pl-7 pr-3 py-1.5 rounded-lg border border-n-weak bg-n-alpha-1 dark:bg-n-solid-2 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-1 focus:ring-n-brand"
          placeholder="Buscar agente..."
        />
      </div>
    </div>

    <div v-if="loadingAgents && !agents.length" class="flex items-center justify-center gap-2 py-10 text-n-slate-9 text-xs">
      <span class="i-lucide-loader-circle size-4 animate-spin" />
      Carregando agentes...
    </div>

    <div
      v-else-if="!loadingAgents && !filteredAgents.length && !errorMsg"
      class="flex flex-col items-center justify-center gap-2 py-10 text-n-slate-9 text-xs text-center px-4"
    >
      <span class="i-lucide-users size-8 opacity-40" />
      <span v-if="searchQuery">Nenhum agente encontrado para "{{ searchQuery }}"</span>
      <span v-else>Nenhum outro agente disponível</span>
    </div>

    <div v-else class="flex-1 overflow-y-auto">
      <button
        v-for="agent in filteredAgents"
        :key="agent.id"
        class="flex items-center gap-3 w-full px-3 py-2.5 hover:bg-n-alpha-2 transition-colors text-left min-w-0"
        @click="openChat(agent)"
      >
        <div class="relative flex-shrink-0">
          <div
            class="flex items-center justify-center size-8 rounded-full text-white font-semibold text-xs"
            :style="{ backgroundColor: avatarBg(agent.id) }"
          >
            {{ initial(agent.name) }}
          </div>
          <span
            class="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-n-background"
            :class="dotColor(agent.availability_status)"
          />
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-n-slate-12 truncate leading-tight">{{ agent.name }}</div>
          <div class="text-xs text-n-slate-9 leading-tight">
            {{ agent.role === 'administrator' ? 'Administrador' : 'Agente' }}
            · {{ dotLabel(agent.availability_status) }}
          </div>
        </div>
        <span class="i-lucide-chevron-right size-4 text-n-slate-8 flex-shrink-0" />
      </button>
    </div>
  </template>

  <!-- CHAT -->
  <template v-else>
    <div v-if="loading" class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-9 text-sm">
      <span class="i-lucide-loader-circle size-6 animate-spin" />
      <span>Abrindo conversa...</span>
    </div>

    <template v-else-if="!errorMsg">
      <!-- Mensagens -->
      <div ref="messagesEl" class="flex-1 overflow-y-auto p-3 flex flex-col gap-2 min-h-0">
        <div
          v-if="!messages.length"
          class="flex flex-col items-center justify-center gap-2 h-full text-n-slate-9 text-sm text-center"
        >
          <span class="i-lucide-message-circle size-10 opacity-30" />
          <span class="leading-snug">Nenhuma mensagem ainda.<br />Diga olá 👋</span>
        </div>

        <div
          v-for="msg in messages"
          :key="msg.id"
          class="flex"
          :class="isMe(msg) ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[82%] rounded-2xl px-3 py-2 text-sm break-words"
            :class="
              isMe(msg)
                ? 'bg-n-brand text-white rounded-br-sm'
                : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm'
            "
          >
            <p class="leading-snug whitespace-pre-wrap">{{ msg.content }}</p>
            <span
              class="text-[10px] block mt-0.5 opacity-60"
              :class="isMe(msg) ? 'text-right' : 'text-left'"
            >
              {{ fmt(msg.created_at) }}
              <span v-if="String(msg.id).startsWith('temp-')"> · enviando...</span>
            </span>
          </div>
        </div>
      </div>

      <!-- Input -->
      <div class="flex items-end gap-2 px-3 py-2 border-t border-n-weak flex-shrink-0">
        <textarea
          v-model="newMessage"
          class="flex-1 text-sm px-3 py-2 rounded-xl border border-n-weak bg-n-background text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-1 focus:ring-n-brand resize-none min-w-0 leading-tight"
          placeholder="Mensagem... (Enter envia)"
          rows="1"
          style="max-height:80px; overflow-y:auto;"
          :disabled="sending"
          @keydown.enter.exact.prevent="sendMessage"
          @keydown.enter.shift.exact="newMessage += '\n'"
        />
        <button
          class="flex items-center justify-center size-8 rounded-xl transition-colors flex-shrink-0 mb-0.5"
          :class="newMessage.trim() && !sending ? 'bg-n-brand text-white hover:opacity-90' : 'bg-n-alpha-2 text-n-slate-8 cursor-not-allowed'"
          :disabled="!newMessage.trim() || sending"
          title="Enviar (Enter)"
          @click="sendMessage"
        >
          <span v-if="sending" class="i-lucide-loader-circle size-4 animate-spin" />
          <span v-else class="i-lucide-send-horizontal size-4" />
        </button>
      </div>
      <p class="text-center text-[10px] text-n-slate-8 pb-1.5 flex-shrink-0">Shift+Enter para nova linha</p>
    </template>
  </template>
</template>
