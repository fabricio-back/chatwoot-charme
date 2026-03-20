<script setup>
/* global axios */
import { ref, watch, onUnmounted, nextTick } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const emit = defineEmits(['close']);

const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const activeTab = ref('conversations');
const agents = ref([]);
const myConversations = ref([]);
const selectedAgents = ref([]);
const openConversation = ref(null);
const messages = ref([]);
const newMessage = ref('');
const inboxId = ref(null);
const loading = ref(false);
const sending = ref(false);
const errorMsg = ref('');
const messagesEl = ref(null);
let pollTimer = null;

const INBOX_NAME = 'Chat Interno';

const agentInitial = (name) => (name || '?')[0].toUpperCase();

const agentColor = (id) => {
  const p = ['#aa0101','#b45309','#047857','#1d4ed8','#6d28d9','#be185d','#0891b2','#65a30d','#7c3aed','#dc2626'];
  return p[Math.abs(id) % p.length];
};

const formatTime = (ts) => {
  if (!ts) return '';
  const d = new Date(ts * 1000);
  const now = new Date();
  return d.toDateString() === now.toDateString()
    ? d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};

const isMyMessage = (msg) => msg.sender?.id === currentUser.value?.id;

const toggleAgent = (agent) => {
  const idx = selectedAgents.value.findIndex((a) => a.id === agent.id);
  if (idx === -1) selectedAgents.value.push(agent);
  else selectedAgents.value.splice(idx, 1);
};

const isSelected = (agent) => selectedAgents.value.some((a) => a.id === agent.id);

const fetchInbox = async () => {
  if (!accountId.value) return;
  const res = await axios.get(`/api/v1/accounts/${accountId.value}/inboxes`);
  const list = res.data?.payload || [];
  let inbox = list.find((i) => i.name === INBOX_NAME);
  if (!inbox) {
    if (currentUser.value?.role !== 'administrator') return;
    const created = await axios.post(`/api/v1/accounts/${accountId.value}/inboxes`, {
      name: INBOX_NAME,
      channel: { type: 'api', webhook_url: '' },
    });
    inbox = created.data;
  }
  inboxId.value = inbox.id;
};

const fetchAgents = async () => {
  if (!accountId.value) return;
  const res = await axios.get(`/api/v1/accounts/${accountId.value}/agents`);
  agents.value = (res.data || []).filter((a) => a.id !== currentUser.value?.id);
};

const fetchMyConversations = async () => {
  if (!inboxId.value || !accountId.value) return;
  try {
    const res = await axios.get(`/api/v1/accounts/${accountId.value}/conversations`, {
      params: { inbox_id: inboxId.value, assignee_type: 'assigned', status: 'open', page: 1 },
    });
    const all = res.data?.data?.payload || [];
    const myId = currentUser.value?.id;
    myConversations.value = all.filter((c) => {
      const isAssignee = c.meta?.assignee?.id === myId;
      const isParticipant = (c.participants || []).some((p) => p.id === myId);
      return isAssignee || isParticipant;
    });
  } catch {
    myConversations.value = [];
  }
};

const convTitle = (conv) => {
  const name = conv.meta?.sender?.name || '';
  return name.startsWith('DM: ') ? name.slice(4) : name || `#${conv.id}`;
};

const convPreview = (conv) => {
  const last = conv.last_non_activity_message;
  if (!last?.content) return 'Sem mensagens';
  const prefix = last.sender?.id === currentUser.value?.id ? 'Você: ' : '';
  return prefix + last.content.slice(0, 60) + (last.content.length > 60 ? '…' : '');
};

const openConv = async (conv) => {
  if (!accountId.value) return;
  openConversation.value = { id: conv.id, title: convTitle(conv) };
  messages.value = [];
  errorMsg.value = '';
  loading.value = true;
  stopPoll();
  await fetchMessages(conv.id);
  loading.value = false;
  startPoll(conv.id);
};

const findOrCreateContact = async (email, name) => {
  try {
    const res = await axios.get(`/api/v1/accounts/${accountId.value}/contacts/search`, {
      params: { q: email, include_contacts: true },
    });
    const list = res.data?.payload || [];
    if (list.length > 0) return list[0].id;
  } catch { /* fall through */ }
  const created = await axios.post(`/api/v1/accounts/${accountId.value}/contacts`, {
    name,
    email,
    account_id: accountId.value,
  });
  return created.data.id;
};

const findOrCreateConversation = async (contactId, participantIds) => {
  if (!contactId) throw new Error('contactId indefinido');
  const res = await axios.get(
    `/api/v1/accounts/${accountId.value}/contacts/${contactId}/conversations`
  );
  const convs = res.data?.payload || [];
  const existing = convs.find((c) => c.inbox_id === inboxId.value);
  if (existing) return existing.id;
  const created = await axios.post(`/api/v1/accounts/${accountId.value}/conversations`, {
    inbox_id: inboxId.value,
    contact_id: contactId,
    assignee_id: currentUser.value?.id,
  });
  const convId = created.data.id;
  const all = [currentUser.value?.id, ...(participantIds || [])].filter(Boolean);
  await axios
    .post(`/api/v1/accounts/${accountId.value}/conversations/${convId}/participants`, { user_ids: all })
    .catch(() => {});
  return convId;
};

const startConversation = async () => {
  if (!selectedAgents.value.length || !accountId.value || !currentUser.value?.id) return;
  loading.value = true;
  errorMsg.value = '';
  stopPoll();
  try {
    if (!inboxId.value) await fetchInbox();
    const myId = currentUser.value.id;
    let contactId, title;
    if (selectedAgents.value.length === 1) {
      const other = selectedAgents.value[0];
      const pair = [Math.min(myId, other.id), Math.max(myId, other.id)].join('-');
      contactId = await findOrCreateContact(
        `internal-dm-${pair}@system.local`,
        `DM: ${currentUser.value.name || 'Eu'} & ${other.name}`
      );
      title = other.name;
    } else {
      const ids = [myId, ...selectedAgents.value.map((a) => a.id)].sort();
      const names = [currentUser.value.name || 'Eu', ...selectedAgents.value.map((a) => a.name)];
      contactId = await findOrCreateContact(
        `internal-group-${ids.join('-')}@system.local`,
        `Grupo: ${names.join(', ')}`
      );
      title = `Grupo: ${selectedAgents.value.map((a) => a.name).join(', ')}`;
    }
    const convId = await findOrCreateConversation(contactId, selectedAgents.value.map((a) => a.id));
    openConversation.value = { id: convId, title };
    messages.value = [];
    selectedAgents.value = [];
    await fetchMessages(convId);
    startPoll(convId);
    await fetchMyConversations();
    activeTab.value = 'conversations';
  } catch (e) {
    errorMsg.value = e.message || 'Erro ao iniciar conversa.';
  } finally {
    loading.value = false;
  }
};

const fetchMessages = async (convId) => {
  const id = convId || openConversation.value?.id;
  if (!id || !accountId.value) return;
  try {
    const res = await axios.get(
      `/api/v1/accounts/${accountId.value}/conversations/${id}/messages`
    );
    const all = res.data?.payload || [];
    const filtered = all
      .filter((m) => m.message_type !== 2 && m.message_type !== 3)
      .sort((a, b) => a.created_at - b.created_at);
    const prev = messages.value.length;
    messages.value = filtered;
    if (filtered.length !== prev) scrollBottom();
  } catch { /* ignore */ }
};

const sendMessage = async () => {
  const text = newMessage.value.trim();
  if (!text || sending.value || !openConversation.value || !accountId.value) return;
  newMessage.value = '';
  sending.value = true;
  try {
    await axios.post(
      `/api/v1/accounts/${accountId.value}/conversations/${openConversation.value.id}/messages`,
      { content: text, message_type: 'outgoing', private: true }
    );
    await fetchMessages();
  } catch {
    newMessage.value = text;
  } finally {
    sending.value = false;
  }
};

const startPoll = (convId) => {
  stopPoll();
  pollTimer = setInterval(() => fetchMessages(convId), 3000);
};
const stopPoll = () => {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
};

const scrollBottom = () => {
  nextTick(() => {
    if (messagesEl.value) messagesEl.value.scrollTop = messagesEl.value.scrollHeight;
  });
};

const backFromConversation = () => {
  stopPoll();
  openConversation.value = null;
  messages.value = [];
  errorMsg.value = '';
  fetchMyConversations();
};

watch(activeTab, (tab) => {
  selectedAgents.value = [];
  if (tab === 'conversations') fetchMyConversations();
});

watch(
  () => currentUser.value?.id,
  async (id) => {
    if (!id || !accountId.value) return;
    await fetchInbox().catch(() => {});
    await Promise.all([fetchAgents(), fetchMyConversations()]);
  },
  { immediate: true }
);

onUnmounted(stopPoll);
</script>

<template>
  <!-- Header -->
  <div class="flex items-center gap-2 px-3 py-2 border-b border-n-weak flex-shrink-0">
    <button
      v-if="openConversation"
      class="flex items-center justify-center size-7 rounded-lg hover:bg-n-alpha-2 transition-colors text-n-slate-11"
      @click="backFromConversation"
    >
      <span class="i-lucide-arrow-left size-4" />
    </button>
    <span class="flex-grow font-semibold text-sm text-n-slate-12 truncate">
      {{ openConversation ? openConversation.title : 'Chat Interno' }}
    </span>
    <button
      class="flex items-center justify-center size-7 rounded-lg hover:bg-n-alpha-2 transition-colors text-n-slate-11"
      @click="emit('close')"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>

  <!-- Tabs -->
  <div v-if="!openConversation" class="flex border-b border-n-weak flex-shrink-0">
    <button
      class="flex-1 py-2 text-xs font-medium transition-colors border-b-2"
      :class="activeTab === 'conversations' ? 'border-n-brand text-n-brand' : 'border-transparent text-n-slate-11 hover:text-n-slate-12'"
      @click="activeTab = 'conversations'"
    >
      Conversas
    </button>
    <button
      class="flex-1 py-2 text-xs font-medium transition-colors border-b-2"
      :class="activeTab === 'agents' ? 'border-n-brand text-n-brand' : 'border-transparent text-n-slate-11 hover:text-n-slate-12'"
      @click="activeTab = 'agents'"
    >
      Agentes
    </button>
  </div>

  <!-- Error -->
  <div
    v-if="errorMsg"
    class="mx-3 mt-2 p-2 rounded-lg bg-red-50 dark:bg-red-950 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-300 text-xs flex gap-2 flex-shrink-0"
  >
    <span class="i-lucide-alert-circle size-4 flex-shrink-0 mt-0.5" />
    <span>{{ errorMsg }}</span>
  </div>

  <!-- TAB: Conversas -->
  <div v-if="!openConversation && activeTab === 'conversations'" class="flex-1 overflow-y-auto">
    <div
      v-if="!myConversations.length"
      class="flex flex-col items-center justify-center h-32 text-n-slate-10 text-xs gap-2 text-center px-4"
    >
      <span class="i-lucide-message-square-dashed size-8 opacity-40" />
      Nenhuma conversa ainda.<br />
      Vá em <strong>Agentes</strong> para iniciar.
    </div>
    <button
      v-for="conv in myConversations"
      :key="conv.id"
      class="flex items-center gap-3 w-full px-3 py-2.5 hover:bg-n-alpha-2 transition-colors text-left min-w-0"
      @click="openConv(conv)"
    >
      <div class="flex items-center justify-center size-8 rounded-full flex-shrink-0 text-white bg-n-brand">
        <span class="i-lucide-message-square-text size-4" />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-baseline justify-between gap-1">
          <span class="text-sm font-medium text-n-slate-12 truncate">{{ convTitle(conv) }}</span>
          <span class="text-[10px] text-n-slate-10 flex-shrink-0">{{ formatTime(conv.last_activity_at) }}</span>
        </div>
        <div class="text-xs text-n-slate-10 truncate">{{ convPreview(conv) }}</div>
      </div>
    </button>
  </div>

  <!-- TAB: Agentes -->
  <div v-if="!openConversation && activeTab === 'agents'" class="flex-1 overflow-y-auto flex flex-col min-h-0">
    <div class="flex-1 overflow-y-auto">
      <div v-if="!agents.length" class="flex items-center justify-center h-24 text-n-slate-10 text-xs gap-2">
        <span class="i-lucide-loader-circle size-4 animate-spin" />
        Carregando agentes...
      </div>
      <button
        v-for="agent in agents"
        :key="agent.id"
        class="flex items-center gap-3 w-full px-3 py-2.5 hover:bg-n-alpha-2 transition-colors text-left min-w-0"
        :class="{ 'bg-n-alpha-2': isSelected(agent) }"
        @click="toggleAgent(agent)"
      >
        <div
          class="flex items-center justify-center size-8 rounded-full flex-shrink-0 text-white font-semibold text-xs"
          :style="{ backgroundColor: agentColor(agent.id) }"
        >
          {{ agentInitial(agent.name) }}
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-n-slate-12 truncate">{{ agent.name }}</div>
          <div class="text-xs text-n-slate-10">{{ agent.role === 'administrator' ? 'Administrador' : 'Agente' }}</div>
        </div>
        <div
          class="size-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors"
          :class="isSelected(agent) ? 'bg-n-brand border-n-brand' : 'border-n-weak'"
        >
          <span v-if="isSelected(agent)" class="i-lucide-check size-3 text-white" />
        </div>
      </button>
    </div>
    <Transition
      enter-active-class="transition-all duration-150 ease-out"
      enter-from-class="opacity-0 translate-y-2"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition-all duration-100 ease-in"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 translate-y-2"
    >
      <div
        v-if="selectedAgents.length > 0"
        class="border-t border-n-weak p-3 flex items-center gap-2 flex-shrink-0 bg-n-background"
      >
        <div class="flex-1 min-w-0">
          <div class="text-xs font-medium text-n-slate-12 truncate">
            {{ selectedAgents.length === 1 ? selectedAgents[0].name : `Grupo com ${selectedAgents.length} agentes` }}
          </div>
          <div class="text-[10px] text-n-slate-10">
            {{ selectedAgents.length === 1 ? 'Conversa 1:1' : 'Conversa em grupo' }}
          </div>
        </div>
        <button
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-n-brand text-white text-xs font-medium hover:opacity-90 transition-opacity flex-shrink-0"
          :disabled="loading"
          @click="startConversation"
        >
          <span v-if="loading" class="i-lucide-loader-circle size-3.5 animate-spin" />
          <span v-else class="i-lucide-send-horizontal size-3.5" />
          Iniciar
        </button>
      </div>
    </Transition>
  </div>

  <!-- Conversa aberta -->
  <template v-if="openConversation">
    <div v-if="loading" class="flex items-center justify-center flex-1 text-n-slate-10 gap-2 text-sm">
      <span class="i-lucide-loader-circle size-5 animate-spin" />
      Carregando...
    </div>
    <div v-else ref="messagesEl" class="flex-1 overflow-y-auto p-3 flex flex-col gap-2">
      <div
        v-for="msg in messages"
        :key="msg.id"
        class="flex"
        :class="isMyMessage(msg) ? 'justify-end' : 'justify-start'"
      >
        <div
          class="max-w-[80%] rounded-2xl px-3 py-2 text-sm break-words"
          :class="isMyMessage(msg) ? 'bg-n-brand text-white rounded-br-sm' : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm'"
        >
          <p v-if="!isMyMessage(msg)" class="text-[10px] font-medium opacity-70 mb-0.5 leading-none">
            {{ msg.sender?.name || 'Agente' }}
          </p>
          <p class="leading-snug whitespace-pre-wrap">{{ msg.content }}</p>
          <span class="text-[10px] block mt-1 opacity-70" :class="isMyMessage(msg) ? 'text-right' : 'text-left'">
            {{ formatTime(msg.created_at) }}
          </span>
        </div>
      </div>
      <div v-if="!messages.length" class="flex-1 flex items-center justify-center text-n-slate-10 text-sm text-center py-8">
        Nenhuma mensagem ainda.<br />Diga olá! 👋
      </div>
    </div>
    <div class="flex items-center gap-2 px-3 py-2 border-t border-n-weak flex-shrink-0">
      <input
        v-model="newMessage"
        class="flex-1 text-sm px-3 py-1.5 rounded-lg border border-n-weak bg-n-background text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-1 focus:ring-n-brand min-w-0"
        placeholder="Mensagem..."
        :disabled="sending || loading"
        @keydown.enter.prevent="sendMessage"
      />
      <button
        class="flex items-center justify-center size-8 rounded-lg transition-colors flex-shrink-0"
        :class="newMessage.trim() && !sending ? 'bg-n-brand text-white hover:opacity-90' : 'bg-n-alpha-2 text-n-slate-9 cursor-not-allowed'"
        :disabled="!newMessage.trim() || sending || loading"
        @click="sendMessage"
      >
        <span class="i-lucide-send-horizontal size-4" />
      </button>
    </div>
  </template>
</template>