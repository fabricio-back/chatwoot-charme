# 📦 Brand Assets - Charme

Coloque suas imagens personalizadas nesta pasta.

## 📁 Arquivos Necessários

### 1. **logo.png** (Obrigatório)
- **Formato**: PNG com transparência
- **Tamanho recomendado**: 200x50px
- **Onde aparece**: Header do dashboard, emails, sidebar
- **Dica**: Use fundo transparente para melhor resultado

### 2. **logo_thumbnail.png** (Obrigatório)
- **Formato**: PNG ou ICO
- **Tamanho**: 32x32px ou 64x64px
- **Onde aparece**: Favicon (ícone da aba do navegador)
- **Dica**: Mantenha simples - ícones pequenos devem ser reconhecíveis

### 3. **banner.png** (Opcional)
- **Formato**: PNG ou JPG
- **Tamanho recomendado**: 1200x600px
- **Onde aparece**: Tela de login/cadastro
- **Dica**: Use imagem que represente sua marca

---

## 🎨 Como Criar as Imagens

### Opção 1: Canva (Recomendado)
1. Acesse https://www.canva.com
2. Crie designs com os tamanhos especificados
3. Baixe como PNG

### Opção 2: Photopea (Online Grátis)
1. Acesse https://www.photopea.com
2. Crie arquivos com dimensões corretas
3. Exporte como PNG

### Opção 3: Figma/Sketch/Photoshop
Use suas ferramentas preferidas

---

## 📋 Checklist

Antes de fazer o build, certifique-se:

- [ ] `logo.png` está na pasta (200x50px recomendado)
- [ ] `logo_thumbnail.png` está na pasta (32x32px recomendado)
- [ ] (Opcional) `banner.png` está na pasta (1200x600px)
- [ ] Imagens têm boa qualidade
- [ ] Arquivos PNG usam transparência quando possível
- [ ] Tamanho total < 2MB (para builds rápidos)

---

## 🚀 Após Adicionar as Imagens

Execute o rebuild:

```bash
docker build -f Dockerfile.full -t meu-chatwoot-custom:v1.1 .
docker compose up -d
```

---

## 💡 Exemplos de Logo

Boas práticas:
- ✅ Horizontal (largura > altura)
- ✅ Legível em tamanhos pequenos
- ✅ Contraste adequado com fundo escuro/claro
- ✅ Fundo transparente
- ❌ Texto muito pequeno
- ❌ Detalhes excessivos
