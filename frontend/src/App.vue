<template>
  <div class="app-shell">
    <div v-if="showKeyModal" class="modal-mask">
      <div class="modal-card">
        <h2>接入 DeepSeek</h2>
        <p>必须填写真实 API Key 后才能使用。</p>
        <input v-model="apiKeyInput" type="password" placeholder="DeepSeek API Key" autocomplete="new-password" name="deepseek_key_no_save" @keydown.enter="saveApiKey" />
        <label class="modal-label">模型</label>
        <select v-model="modelInput">
          <option value="deepseek-chat">deepseek-chat</option>
          <option value="deepseek-reasoner">deepseek-reasoner</option>
        </select>
        <button class="primary full" @click="saveApiKey">本次使用并进入</button>
        <button class="light full" @click="clearApiKey">清除本地 Key</button>
        <p class="msg error" v-if="keyMessage">{{ keyMessage }}</p>
      </div>
    </div>

    <header class="topbar hero-topbar">
      <div class="hero-brand">
        <div class="hero-badge">
          <img src="/sukoya-icon.png" alt="Sukoya" />
        </div>
        <div class="hero-copy">
          <h1>Sukoyaちゃん</h1>
          <p>Handwriting Engine · 把答案变成可爱的手写版 ✨</p>
        </div>
      </div>
      <div class="hero-actions">
        <button class="light" @click="forceKeyModal">DeepSeek：{{ keyStatus.has_key ? keyStatus.masked : '未接入' }}</button>
      </div>
    </header>

    <main class="layout">
      <section class="card input-card panel-card">
        <div class="card-head">
          <h2>题目内容</h2>
          <span>{{ rawText.length }} 字</span>
        </div>
        <div class="upload-box" @dragover.prevent @drop.prevent="handleDrop">
          <input ref="fileInput" type="file" accept=".pdf,.docx,.txt,.rtf,.png,.jpg,.jpeg,.webp,.bmp" @change="handleFileChange" hidden />
          <button @click="$refs.fileInput.click()">上传 PDF / Word / 图片</button>
          <span>{{ uploadedName || '也可以直接粘贴题目' }}</span>
        </div>
        <textarea v-model="rawText" spellcheck="false" placeholder=""></textarea>
      </section>

      <section class="center-stack panel-card">
        <section class="card answer-card third-card">
          <div class="card-head">
            <h2>答案预览</h2>
            <span>{{ answerText.length ? answerText.length + ' 字' : '未生成' }}</span>
          </div>
          <div class="answer-edit-toolbar">
            <button v-if="!answerEditing" @click="startAnswerEdit" :disabled="!answerText.trim()">编辑答案</button>
            <button v-if="answerEditing" class="primary" @click="finishAnswerEdit">结束更改</button>
            <button v-if="answerEditing" @click="cancelAnswerEdit">取消</button>
          </div>
          <textarea
            v-if="answerEditing"
            class="answer-edit-box"
            v-model="editableAnswerText"
            spellcheck="false"
            placeholder="在这里修改答案，点“结束更改”后生成手写版会使用修改后的版本。"
          ></textarea>
          <div v-else class="answer-preview single-preview"><pre class="answer-pre">{{ answerPreviewText }}</pre></div>
        </section>

        <section class="card diagram-card third-card">
          <div class="card-head">
            <h2>图示预览</h2>
            <span>{{ diagramSvg ? (diagramTitle || '已生成') : '未生成' }}</span>
          </div>
          <div class="diagram-panel-fixed">
            <div class="diagram-canvas" v-if="diagramSvg" v-html="diagramSvg"></div>
            <div class="diagram-empty" v-else>需要画图时，点右侧“生成图示”。</div>
          </div>
          <div class="mini-tip">手写生成时会把图示自动附到最后一页。</div>
        </section>

        <section class="card handwriting-card third-card">
          <div class="card-head">
            <h2>手写答案预览</h2>
            <span>{{ previewImages.length ? previewImages.length + ' 页' : '未生成' }}</span>
          </div>
          <div class="image-preview">
            <div v-if="previewImages.length === 0" class="empty">生成后在这里查看手写版。</div>
            <img v-for="(src, index) in previewImages" :key="index" :src="src" :alt="`page-${index + 1}`" />
          </div>
        </section>
      </section>

      <aside class="card tools-card panel-card">
        <h2>功能栏</h2>

        <button class="primary" @click="aiAction('answer')" :disabled="loadingAi">生成答案</button>
        <button @click="aiAction('multi')" :disabled="loadingAi">多题短答</button>
        <button @click="aiAction('steps')" :disabled="loadingAi">补必要步骤</button>
        <button @click="aiAction('formula')" :disabled="loadingAi">整理公式</button>
        <button @click="aiAction('natural')" :disabled="loadingAi">改得像手写</button>
        <button @click="aiAction('search')" :disabled="loadingAi">资料核对</button>

        <div class="divider"></div>
        <button class="primary" @click="generateDiagram" :disabled="loadingAi">生成图示</button>
        <button @click="makeLocalDiagram">本地测试图</button>
        <button @click="insertDiagramNote" :disabled="!diagramSvg">插入答案</button>
        <button @click="downloadDiagramSvg" :disabled="!diagramSvg">导出 SVG</button>
        <button @click="downloadDiagramPng" :disabled="!diagramSvg">导出 PNG</button>
        <button @click="clearDiagram" :disabled="!diagramSvg">清空图示</button>

        <div class="divider"></div>

        <label>使用模型
          <select v-model="modelInput">
            <option value="deepseek-chat">deepseek-chat</option>
            <option value="deepseek-reasoner">deepseek-reasoner</option>
          </select>
        </label>
        <label>书写体
          <select v-model="settings.handwriting_profile" @change="syncProfileFont">
            <option value="sukoya">sukoya</option>
            <option value="seuomi">seuomi</option>
          </select>
        </label>
        <label>字体
          <select v-model="settings.font_option" @change="syncFontProfile">
            <option v-for="font in fonts" :key="font" :value="font">{{ displayFontName(font) }}</option>
          </select>
        </label>
        <label class="font-upload-row">
          <input type="file" accept=".ttf,.otf" @change="uploadPersonalFont" />
          <span>导入我的字体</span>
        </label>
        <label>字号
          <input type="number" v-model="settings.font_size" min="18" max="56" />
        </label>
        <label>行距
          <input type="number" v-model="settings.line_spacing" min="28" max="80" />
        </label>
        <label>混乱度：{{ settings.handwriting_chaos }}
          <input type="range" v-model="settings.handwriting_chaos" min="0" max="100" step="5" />
          <span class="setting-hint">{{ chaosLabel }}</span>
        </label>
        <label>晕染次数：{{ settings.ink_bleed_count }}
          <input type="range" v-model="settings.ink_bleed_count" min="0" max="3" step="1" />
          <span class="setting-hint">{{ bleedLabel }}</span>
        </label>
        <label>纸张
          <select v-model="paperMode">
            <option value="line">横线纸</option>
            <option value="blank">白纸</option>
          </select>
        </label>
        <label class="check-row">
          <input type="checkbox" v-model="insertDiagramInHandwriting" />
          <span>手写版插入图示</span>
        </label>

        <button class="primary" @click="generatePreview" :disabled="working">
          {{ insertDiagramInHandwriting ? '生成手写答案（含图）' : '生成手写答案（不含图）' }}
        </button>
        <button @click="downloadPdf" :disabled="working">
          {{ insertDiagramInHandwriting ? '导出 PDF（含图）' : '导出 PDF（不含图）' }}
        </button>
        <button @click="copyAnswer">复制答案</button>
        <button @click="saveCurrentToCache">存入缓存</button>
        <button @click="clearCurrentCache">清空当前</button>
        <button @click="forceKeyModal">API 设置</button>

        <p class="msg" v-if="message">{{ message }}</p>
      </aside>
    </main>

    <button class="cache-toggle" @click="cacheOpen = !cacheOpen">缓存库 {{ cacheItems.length }}</button>
    <section v-if="cacheOpen" class="cache-drawer">
      <div class="cache-head">
        <div>
          <h2>缓存库</h2>
          <p>只保存题目和答案，不保存 API Key。</p>
        </div>
        <button class="light small" @click="cacheOpen = false">收起</button>
      </div>
      <input v-model="cacheKeyword" class="cache-search" placeholder="搜索题目 / 答案" />
      <div class="cache-actions">
        <button @click="saveCurrentToCache">保存当前</button>
        <button @click="clearAllCache">清缓存</button>
      </div>
      <div class="cache-list">
        <div v-if="filteredCacheItems.length === 0" class="cache-empty">暂无缓存。</div>
        <article v-for="item in filteredCacheItems" :key="item.id" class="cache-item">
          <div class="cache-item-title">{{ item.title }}</div>
          <div class="cache-item-meta">{{ item.time }} · {{ item.answerLength || 0 }} 字</div>
          <p>{{ item.preview }}</p>
          <div class="cache-item-actions">
            <button class="small" @click="restoreCache(item)">打开</button>
            <button class="small danger" @click="deleteCache(item.id)">删除</button>
          </div>
        </article>
      </div>
    </section>
  </div>
</template>

<script>
/* eslint-disable */
const CACHE_KEY = 'sukoya_homework_cache_items_v2';

function escapeHtml(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\n/g, '<br />');
}

async function readJson(res) {
  const text = await res.text();
  try {
    return text ? JSON.parse(text) : {};
  } catch (error) {
    throw new Error(text && text.includes('Proxy error') ? '后端没有启动成功，请看 Backend 窗口红字。' : '接口返回异常，不是 JSON。');
  }
}


function repairLatexArtifacts(text) {
  let s = String(text || '');
  const commandMap = {
    cdot: ' x ', times: ' x ', neq: '≠', ne: '≠', leq: '≤', le: '≤', geq: '≥', ge: '≥',
    approx: '≈', equiv: '≡', pm: '±', partial: '∂', Delta: 'Δ', delta: 'δ', theta: 'θ',
    alpha: 'α', beta: 'β', gamma: 'γ', lambda: 'λ', mu: 'μ', omega: 'ω', pi: 'π'
  };
  Object.entries(commandMap).forEach(([k, v]) => {
    s = s.replace(new RegExp('\\\\' + k + '\\b', 'g'), v);
  });
  const bareMap = { cdot: ' x ', neq: '≠', leq: '≤', geq: '≥', times: ' x ', approx: '≈', partial: '∂', Delta: 'Δ' };
  Object.entries(bareMap).forEach(([k, v]) => {
    s = s.replace(new RegExp(k, 'g'), v);
  });
  s = s.replace(/\\;/g, ' ').replace(/\\,/g, ' ');
  s = s.replace(/\\left|\\right/g, '');
  s = s.replace(/\$+/g, '');
  s = s.replace(/\\?begin\s*\{?cases\}?/gi, '{\n');
  s = s.replace(/\\?end\s*\{?cases\}?/gi, '');
  s = s.replace(/\\?begin\s*\{?(bmatrix|pmatrix|matrix|vmatrix|Vmatrix)\}?/gi, '\n');
  s = s.replace(/\\?end\s*\{?(bmatrix|pmatrix|matrix|vmatrix|Vmatrix)\}?/gi, '\n');
  s = s.replace(/\\\\/g, '\n');
  s = s.replace(/\s*&\s*/g, '   ');
  s = s.replace(/\\vec\s*\{?([A-Za-z])\}?/g, '$1⃗');
  s = s.replace(/\\overrightarrow\s*\{?([A-Za-z])\}?/g, '$1⃗');
  s = s.replace(/\\hat\s*\{?([A-Za-z])\}?/g, '$1̂');
  s = s.replace(/\\bar\s*\{?([A-Za-z])\}?/g, '$1̄');
  s = s.replace(/\\mathrm\s*\{([^{}]+)\}/g, '$1');
  s = s.replace(/\\mathbf\s*\{([^{}]+)\}/g, '$1');
  s = s.replace(/\\text\s*\{([^{}]+)\}/g, '$1');
  s = s.replace(/\\([A-Za-z]+)/g, '$1');
  s = s.replace(/\{\s*\n/g, '{\n');
  s = s.replace(/\n{3,}/g, '\n\n');
  s = s.replace(/[ \t]{2,}/g, ' ');
  return s;
}
function toUnicodeFractionText(text) {
  const sup = {'0':'⁰','1':'¹','2':'²','3':'³','4':'⁴','5':'⁵','6':'⁶','7':'⁷','8':'⁸','9':'⁹','-':'⁻','+':'⁺'};
  const sub = {'0':'₀','1':'₁','2':'₂','3':'₃','4':'₄','5':'₅','6':'₆','7':'₇','8':'₈','9':'₉','-':'₋','+':'₊'};
  const conv = (a, b) => String(a).split('').map(ch => sup[ch] || ch).join('') + '⁄' + String(b).split('').map(ch => sub[ch] || ch).join('');
  return String(text || '').replace(/(?<![A-Za-z0-9])(-?\d{1,3})\/(\d{1,3})(?![A-Za-z0-9])/g, (_, a, b) => conv(a, b));
}


function scrubStudentAnswer(text) {
  let s = String(text || '');

  // Remove AI self-check/self-correction fragments. Homework answers should not contain inner monologue.
  s = s.replace(/直线与平面平行无交点[？?]\s*检查[：:][\s\S]*?所以\s*直线平行于平面且不在平面上[，,]无交点。?/g, '直线与平面平行且无交点。');
  s = s.replace(/无交点[？?]\s*检查[：:][\s\S]*?所以\s*/g, '');
  s = s.replace(/([。；;，,]?\s*)?(检查|验算|反过来检查|再检查|核对|说明一下|注意|这里需要注意)[：:][^。\n]*[。]?/g, '');
  s = s.replace(/[^。\n；;]*[？?][^。\n；;]*(?:[。；;]|$)/g, '');

  // Remove verbose AI-ish confirmation words and unnecessary metaphors.
  s = s.replace(/确实/g, '');
  s = s.replace(/形状像[^。\n]*[。.]?/g, '');
  s = s.replace(/可以发现/g, '');
  s = s.replace(/不难看出/g, '');
  s = s.replace(/综上所述[，,]?/g, '');
  s = s.replace(/因此可知[，,]?/g, '所以');

  // Clean common residue after simplification.
  s = s.replace(/[×·]/g, ' x ');
  s = s.replace(/(\d)\s*x\s*(?=\d)/g, '$1 x ');
  s = s.replace(/0\s*\*\s*t/g, '0');
  s = s.replace(/([=≈≠≤≥])\s*0\s*\+\s*1\s*=\s*0\s*无解/g, '$1 1≠0，无解');
  s = s.replace(/平行直线平行于平面/g, '平行于平面');
  s = s.replace(/直线与平面平行直线/g, '直线');
  s = s.replace(/平行且无交点。直线平行于平面且不在平面上，无交点。?/g, '平行且无交点。');

  // Keep punctuation compact.
  s = s.replace(/\s+([，。；：])/g, '$1');
  s = s.replace(/([，。：；]){2,}/g, '$1');
  s = s.replace(/[ \t]{2,}/g, ' ');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}


function normalizeAnswerText(text) {
  let out = repairLatexArtifacts(String(text || ''));
  out = out.replace(/```[a-zA-Z]*\n?/g, '').replace(/```/g, '');
  out = out.replace(/^\s*(答题思路|正式答案|最终答案|参考答案|答案预览|解析|总结)\s*[:：]?\s*/gm, '');
  out = out.replace(/^\s*[-*#]+\s*/gm, '');
  out = scrubStudentAnswer(out);
  out = out.replace(/\n{3,}/g, '\n\n').trim();
  return out;
}

function escapePlain(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function cleanLatex(raw) {
  return normalizeLatexSyntax(String(raw || '')
    .replace(/^\$\$|\$\$$/g, '')
    .replace(/^\$|\$$/g, '')
    .replace(/^\\\[/, '').replace(/\\\]$/, '')
    .replace(/^\\\(/, '').replace(/\\\)$/, '')
    .trim());
}

function normalizeLatexSyntax(raw) {
  let s = String(raw || '');
  s = s.replace(/\\begin\s*cases/g, '\\begin{cases}');
  s = s.replace(/\\end\s*cases/g, '\\end{cases}');
  s = s.replace(/\\begin\s*\{\s*cases\s*\}/g, '\\begin{cases}');
  s = s.replace(/\\end\s*\{\s*cases\s*\}/g, '\\end{cases}');
  s = s.replace(/\\begin\s*(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)/g, '\\begin{$1}');
  s = s.replace(/\\end\s*(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)/g, '\\end{$1}');
  s = s.replace(/\\begin\s*\{\s*(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)\s*\}/g, '\\begin{$1}');
  s = s.replace(/\\end\s*\{\s*(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)\s*\}/g, '\\end{$1}');
  s = s.replace(/\\vec\s*([A-Za-z])/g, '\\vec{$1}');
  s = s.replace(/\\hat\s*([A-Za-z])/g, '\\hat{$1}');
  s = s.replace(/\\bar\s*([A-Za-z])/g, '\\bar{$1}');
  s = s.replace(/\\overrightarrow\s*([A-Za-z])/g, '\\vec{$1}');
  s = s.replace(/\\left/g, '').replace(/\\right/g, '');
  s = s.replace(/\\,/g, ' ');
  return s;
}

const LATEX_SYMBOLS = {
  times: '×', cdot: '·', div: '÷', pm: '±', mp: '∓', leq: '≤', le: '≤', geq: '≥', ge: '≥',
  neq: '≠', ne: '≠', approx: '≈', equiv: '≡', infty: '∞', partial: '∂', nabla: '∇', angle: '∠',
  pi: 'π', theta: 'θ', vartheta: 'θ', alpha: 'α', beta: 'β', gamma: 'γ', lambda: 'λ', mu: 'μ',
  omega: 'ω', phi: 'φ', varphi: 'φ', Delta: 'Δ', delta: 'δ', sigma: 'σ', Sigma: 'Σ', sum: 'Σ',
  int: '∫', sin: 'sin', cos: 'cos', tan: 'tan', ln: 'ln', log: 'log', lim: 'lim', det: 'det'
};

function readLatexGroup(str, startIndex) {
  let i = startIndex;
  while (i < str.length && /\s/.test(str[i])) i += 1;
  if (str[i] === '{') {
    let depth = 1;
    let j = i + 1;
    while (j < str.length && depth > 0) {
      if (str[j] === '{') depth += 1;
      else if (str[j] === '}') depth -= 1;
      j += 1;
    }
    if (depth === 0) return { value: str.slice(i + 1, j - 1), end: j };
    return { value: str.slice(i + 1), end: str.length };
  }
  if (str[i] === '\\') {
    const m = str.slice(i).match(/^\\[A-Za-z]+/);
    if (m) return { value: m[0], end: i + m[0].length };
  }
  let j = i;
  if (j < str.length) j += 1;
  while (j < str.length && /[A-Za-z0-9.]/.test(str[j]) && !/[+\-=<>(),;:\[\]{}&\s]/.test(str[j])) j += 1;
  return { value: str.slice(i, j), end: j };
}

function readCommand(str, index) {
  if (str[index] !== '\\') return null;
  const m = str.slice(index + 1).match(/^[A-Za-z]+/);
  if (m) return { name: m[0], end: index + 1 + m[0].length };
  return { name: str[index + 1] || '', end: index + 2 };
}

function renderVector(content, type = 'vec') {
  const body = renderFormulaExpression(content);
  return `<span class="${type}">${body}</span>`;
}

function renderMatrix(content, type = 'bmatrix') {
  const rows = String(content || '').split(/\\\\/).map(row => row.trim()).filter(Boolean);
  const body = rows.map(row => {
    const cells = row.split('&').map(c => `<td>${renderFormulaExpression(c.trim())}</td>`).join('');
    return `<tr>${cells}</tr>`;
  }).join('');
  let left = '[';
  let right = ']';
  if (type === 'pmatrix') { left = '('; right = ')'; }
  if (type === 'vmatrix') { left = '|'; right = '|'; }
  if (type === 'Vmatrix') { left = '‖'; right = '‖'; }
  if (type === 'matrix') { left = ''; right = ''; }
  return `<span class="matrix-wrap"><span class="matrix-bracket">${left}</span><table class="matrix-table">${body}</table><span class="matrix-bracket">${right}</span></span>`;
}

function renderFormulaExpression(raw) {
  const s = normalizeLatexSyntax(raw);
  let out = '';
  let i = 0;
  while (i < s.length) {
    if (s.startsWith('\\begin{', i)) {
      const begin = s.slice(i).match(/^\\begin\{(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)\}/);
      if (begin) {
        const type = begin[1];
        const bodyStart = i + begin[0].length;
        const endToken = `\\end{${type}}`;
        const endPos = s.indexOf(endToken, bodyStart);
        if (endPos >= 0) {
          out += renderMatrix(s.slice(bodyStart, endPos), type);
          i = endPos + endToken.length;
          continue;
        }
      }
    }
    if (s[i] === '\\') {
      const cmd = readCommand(s, i);
      if (cmd) {
        const name = cmd.name;
        if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
          const a = readLatexGroup(s, cmd.end);
          const b = readLatexGroup(s, a.end);
          out += `<span class="frac"><span class="frac-top">${renderFormulaExpression(a.value)}</span><span class="frac-bottom">${renderFormulaExpression(b.value)}</span></span>`;
          i = b.end;
          continue;
        }
        if (name === 'sqrt') {
          const a = readLatexGroup(s, cmd.end);
          out += `<span class="sqrt">√<span class="sqrt-body">${renderFormulaExpression(a.value)}</span></span>`;
          i = a.end;
          continue;
        }
        if (name === 'vec' || name === 'overrightarrow') {
          const a = readLatexGroup(s, cmd.end);
          out += renderVector(a.value, 'vec');
          i = a.end;
          continue;
        }
        if (name === 'hat' || name === 'bar') {
          const a = readLatexGroup(s, cmd.end);
          out += renderVector(a.value, name);
          i = a.end;
          continue;
        }
        if (name === 'mathrm' || name === 'mathbf' || name === 'text') {
          const a = readLatexGroup(s, cmd.end);
          out += escapePlain(a.value);
          i = a.end;
          continue;
        }
        if (LATEX_SYMBOLS[name]) {
          out += escapePlain(LATEX_SYMBOLS[name]);
          i = cmd.end;
          continue;
        }
        // Unknown commands should not leak as raw LaTeX; show readable text instead.
        out += escapePlain(name);
        i = cmd.end;
        continue;
      }
    }
    if (s[i] === '^' || s[i] === '_') {
      const group = readLatexGroup(s, i + 1);
      const tag = s[i] === '^' ? 'sup' : 'sub';
      out += `<${tag}>${renderFormulaExpression(group.value)}</${tag}>`;
      i = group.end;
      continue;
    }
    if (s[i] === '{' || s[i] === '}') { i += 1; continue; }
    out += escapePlain(s[i]);
    i += 1;
  }
  return out.replace(/\s{2,}/g, ' ');
}

function renderInlineFormula(raw) {
  return renderFormulaExpression(cleanLatex(raw));
}

function renderLatexBlock(raw, inline = false) {
  const cls = inline ? 'latex-inline' : 'latex-block';
  return `<span class="${cls}">${renderInlineFormula(raw)}</span>`;
}

function splitLatexSegments(text) {
  const source = normalizeAnswerText(text);
  const regex = /(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)|\$[^$\n]+\$)/g;
  const parts = [];
  let last = 0;
  let m;
  while ((m = regex.exec(source)) !== null) {
    if (m.index > last) parts.push({ type: 'text', value: source.slice(last, m.index) });
    const token = m[0];
    const block = token.startsWith('$$') || token.startsWith('\\[');
    parts.push({ type: 'latex', value: token, block });
    last = m.index + token.length;
  }
  if (last < source.length) parts.push({ type: 'text', value: source.slice(last) });
  return parts;
}

function lineLooksLikeLatex(line) {
  const s = String(line || '').trim();
  if (!s) return false;
  if (/\\(frac|dfrac|tfrac|sqrt|begin|end|sum|int|vec|hat|bar|alpha|beta|theta|lambda|Delta|pi|omega|mu|sin|cos|tan)/.test(s)) return true;
  if (/\$[^$]+\$/.test(s)) return true;
  if (/[=≈≤≥≠]/.test(s) && /[A-Za-z0-9α-ωΑ-Ω]/.test(s)) return true;
  if (/[\^_]/.test(s) && /[A-Za-z0-9]/.test(s)) return true;
  return false;
}

function renderMixedHtml(text) {
  const parts = splitLatexSegments(text);
  if (!parts.length) return '<div class="empty-text">还没有生成答案。</div>';
  return parts.map(part => {
    if (part.type === 'latex') return renderLatexBlock(part.value, !part.block);
    return part.value.split('\n').map(line => {
      if (!line.trim()) return '<br />';
      if (lineLooksLikeLatex(line)) return `<div class="latex-line">${renderInlineFormula(line)}</div>`;
      return `<div class="text-line">${escapePlain(line)}</div>`;
    }).join('');
  }).join('');
}

function renderLatexPreviewHtml(text) {
  const parts = splitLatexSegments(text).filter(p => p.type === 'latex');
  const loose = normalizeAnswerText(text).split('\n').filter(line => lineLooksLikeLatex(line));
  const seen = new Set();
  const items = [];
  parts.forEach(p => { const k = p.value.trim(); if (!seen.has(k)) { seen.add(k); items.push(renderLatexBlock(p.value, false)); } });
  loose.forEach(line => { const k = line.trim(); if (!seen.has(k)) { seen.add(k); items.push(renderLatexBlock(line, false)); } });
  if (!items.length) return '<div class="empty-text">没有检测到公式；AI 生成后这里会显示分数、矩阵、根号等公式预览。</div>';
  return items.map(v => `<div class="latex-preview-item">${v}</div>`).join('');
}

function formulaToHandwriting(raw, inline = false) {
  let s = repairLatexArtifacts(cleanLatex(raw));
  s = s.replace(/\\begin\{cases\}([\s\S]*?)\\end\{cases\}/g, (_, body) => {
    const rows = body.split(/\\\\|\n/).map(v => formulaToHandwriting(v.trim(), true)).filter(Boolean);
    return '{\n' + rows.join('\n') + '\n';
  });
  s = s.replace(/\\begin\{(bmatrix|pmatrix|matrix|vmatrix|Vmatrix|cases)\}([\s\S]*?)\\end\{\1\}/g, (_, type, body) => {
    const rows = body.split(/\\\\/).map(row => row.trim()).filter(Boolean).map(row => {
      const cells = row.split('&').map(c => formulaToHandwriting(c.trim(), true)).join('   ');
      if (type === 'vmatrix') return `| ${cells} |`;
      if (type === 'pmatrix') return `( ${cells} )`;
      return `[ ${cells} ]`;
    });
    return '\n' + rows.join('\n') + '\n';
  });

  function replaceCommandTwoArgs(text, names, render) {
    let out = '';
    let i = 0;
    while (i < text.length) {
      if (text[i] === '\\') {
        const cmd = readCommand(text, i);
        if (cmd && names.includes(cmd.name)) {
          const a = readLatexGroup(text, cmd.end);
          const b = readLatexGroup(text, a.end);
          out += render(a.value, b.value);
          i = b.end;
          continue;
        }
      }
      out += text[i];
      i += 1;
    }
    return out;
  }
  function replaceCommandOneArg(text, names, render) {
    let out = '';
    let i = 0;
    while (i < text.length) {
      if (text[i] === '\\') {
        const cmd = readCommand(text, i);
        if (cmd && names.includes(cmd.name)) {
          const a = readLatexGroup(text, cmd.end);
          out += render(a.value);
          i = a.end;
          continue;
        }
      }
      out += text[i];
      i += 1;
    }
    return out;
  }

  for (let i = 0; i < 5; i += 1) {
    s = replaceCommandTwoArgs(s, ['frac', 'dfrac', 'tfrac'], (a, b) => {
      const top = formulaToHandwriting(a, true);
      const bot = formulaToHandwriting(b, true);
      const simple = top.length <= 9 && bot.length <= 9 && !top.includes('\n') && !bot.includes('\n');
      if (inline || simple) return toUnicodeFractionText(`${top}/${bot}`);
      const bar = '─'.repeat(Math.max(4, Math.min(18, Math.max(top.length, bot.length))));
      return `\n${top}\n${bar}\n${bot}\n`;
    });
    s = replaceCommandOneArg(s, ['sqrt'], a => `√(${formulaToHandwriting(a, true)})`);
    s = replaceCommandOneArg(s, ['vec', 'overrightarrow'], a => `${formulaToHandwriting(a, true)}⃗`);
    s = replaceCommandOneArg(s, ['hat'], a => `${formulaToHandwriting(a, true)}̂`);
    s = replaceCommandOneArg(s, ['bar'], a => `${formulaToHandwriting(a, true)}̄`);
  }
  s = s.replace(/\^\{([^{}]+)\}/g, (_, a) => `^${formulaToHandwriting(a, true)}`);
  s = s.replace(/_\{([^{}]+)\}/g, (_, a) => `_${formulaToHandwriting(a, true)}`);
  Object.entries(LATEX_SYMBOLS).forEach(([k, v]) => { s = s.replace(new RegExp('\\\\' + k + '\\b', 'g'), v); });
  s = s.replace(/\\(left|right|mathrm|mathbf|text)\b/g, '');
  s = s.replace(/\\([A-Za-z]+)/g, '$1');
  s = s.replace(/[{}$]/g, '');
  s = s.replace(/\s+\n/g, '\n').replace(/\n\s+/g, '\n').replace(/[ \t]{2,}/g, ' ');
  return s.trim();
}

function toHandwritingFriendly(text) {
  const parts = splitLatexSegments(text);
  if (!parts.length) return normalizeAnswerText(text);
  let out = '';
  parts.forEach(part => {
    if (part.type === 'latex') {
      out += (part.block ? '\n' : '') + formulaToHandwriting(part.value, !part.block) + (part.block ? '\n' : '');
    } else {
      out += part.value.split('\n').map(line => lineLooksLikeLatex(line) ? formulaToHandwriting(line, false) : line).join('\n');
    }
  });
  out = out.replace(/\$\$/g, '').replace(/\$/g, '');
  out = out.replace(/\n{3,}/g, '\n\n').trim();
  return out;
}

function previewHtml(text) {
  return renderMixedHtml(text || '');
}

function loadCacheItems() {
  try {
    const data = JSON.parse(localStorage.getItem(CACHE_KEY) || '[]');
    return Array.isArray(data) ? data : [];
  } catch (error) {
    console.warn(error);
    return [];
  }
}

function saveCacheItems(items) {
  localStorage.setItem(CACHE_KEY, JSON.stringify(items.slice(0, 60)));
}

function shortTitle(text) {
  const line = String(text || '').split('\n').map(v => v.trim()).find(Boolean) || '未命名作业';
  return line.length > 24 ? `${line.slice(0, 24)}...` : line;
}

function nowText() {
  const d = new Date();
  const pad = n => String(n).padStart(2, '0');
  return `${d.getMonth() + 1}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}


function extractJsonObject(text) {
  const raw = String(text || '').replace(/```json|```/g, '').trim();
  try { return JSON.parse(raw); } catch (e) {}
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    const part = raw.slice(start, end + 1);
    try { return JSON.parse(part); } catch (e) {}
  }
  return null;
}

function clampNumber(v, min, max, def) {
  const n = Number(v);
  if (!Number.isFinite(n)) return def;
  return Math.max(min, Math.min(max, n));
}

function normalizeDiagramSpec(input) {
  const spec = input && typeof input === 'object' ? input : {};
  const type = ['function_plot', 'geometry', 'physics', 'flowchart', 'none'].includes(spec.type) ? spec.type : 'geometry';
  const canvas = spec.canvas || {};
  const width = clampNumber(canvas.width || spec.width, 360, 1200, 680);
  const height = clampNumber(canvas.height || spec.height, 260, 900, 420);
  const out = {
    type,
    title: String(spec.title || (type === 'function_plot' ? '函数图像' : type === 'physics' ? '示意图' : type === 'flowchart' ? '流程图' : '图示')).slice(0, 40),
    canvas: { width, height },
    style: spec.style || 'handwriting'
  };

  if (type === 'none') {
    out.reason = spec.reason || 'not_applicable';
    return out;
  }

  if (type === 'function_plot') {
    out.xRange = Array.isArray(spec.xRange) ? spec.xRange.slice(0, 2).map(Number) : [-5, 5];
    out.yRange = Array.isArray(spec.yRange) ? spec.yRange.slice(0, 2).map(Number) : [-5, 5];
    if (!Number.isFinite(out.xRange[0]) || !Number.isFinite(out.xRange[1]) || out.xRange[0] === out.xRange[1]) out.xRange = [-5, 5];
    if (!Number.isFinite(out.yRange[0]) || !Number.isFinite(out.yRange[1]) || out.yRange[0] === out.yRange[1]) out.yRange = [-5, 5];
    out.showAxes = spec.showAxes !== false;
    out.showGrid = spec.showGrid === true;
    out.curves = Array.isArray(spec.curves) ? spec.curves.slice(0, 4).map(c => ({
      expr: String(c.expr || c.expression || '').slice(0, 80),
      label: '',
      points: Array.isArray(c.points) ? c.points.slice(0, 300) : null
    })).filter(c => c.expr || c.points) : [];
    out.points = Array.isArray(spec.points) ? spec.points.slice(0, 20).map(p => ({
      x: Number(p.x), y: Number(p.y), label: String(p.label || p.name || '').slice(0, 20)
    })).filter(p => Number.isFinite(p.x) && Number.isFinite(p.y)) : [];
    return out;
  }

  out.points = Array.isArray(spec.points) ? spec.points.slice(0, 80).map(p => ({
    name: String(p.name || p.label || '').slice(0, 18),
    x: clampNumber(p.x, -2000, 2000, 0),
    y: clampNumber(p.y, -2000, 2000, 0),
    label: String(p.label || p.name || '').slice(0, 18)
  })) : [];

  out.segments = Array.isArray(spec.segments) ? spec.segments.slice(0, 120) : [];
  out.circles = Array.isArray(spec.circles) ? spec.circles.slice(0, 30) : [];
  out.polygons = Array.isArray(spec.polygons) ? spec.polygons.slice(0, 30) : [];
  out.objects = Array.isArray(spec.objects) ? spec.objects.slice(0, 30) : [];
  out.forces = Array.isArray(spec.forces) ? spec.forces.slice(0, 30) : [];
  out.annotations = Array.isArray(spec.annotations) ? spec.annotations.slice(0, 50) : [];
  out.nodes = Array.isArray(spec.nodes) ? spec.nodes.slice(0, 30) : [];
  out.edges = Array.isArray(spec.edges) ? spec.edges.slice(0, 60) : [];
  return out;
}

function escSvg(text) {
  return String(text || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function jitter(seed, scale = 1) {
  const x = Math.sin(seed * 999.23) * 10000;
  return (x - Math.floor(x) - 0.5) * scale;
}

function roughLine(x1, y1, x2, y2, opt = {}) {
  const sw = opt.strokeWidth || 2;
  const stroke = opt.stroke || '#202020';
  const r = opt.roughness == null ? 1.2 : opt.roughness;
  const s = Math.abs(x1 * 0.13 + y1 * 0.17 + x2 * 0.19 + y2 * 0.23) + 1;
  const p1 = `M ${x1 + jitter(s, r)} ${y1 + jitter(s + 1, r)} L ${x2 + jitter(s + 2, r)} ${y2 + jitter(s + 3, r)}`;
  const p2 = `M ${x1 + jitter(s + 4, r * .8)} ${y1 + jitter(s + 5, r * .8)} L ${x2 + jitter(s + 6, r * .8)} ${y2 + jitter(s + 7, r * .8)}`;
  return `<path d="${p1}" fill="none" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/><path d="${p2}" fill="none" stroke="${stroke}" stroke-width="${Math.max(1, sw * .75)}" stroke-linecap="round" stroke-linejoin="round" opacity="0.45"/>`;
}

function roughPolyline(points, opt = {}) {
  if (!points || points.length < 2) return '';
  let out = '';
  for (let i = 1; i < points.length; i++) out += roughLine(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], opt);
  return out;
}

function roughRect(x, y, w, h, opt = {}) {
  return roughLine(x, y, x + w, y, opt) + roughLine(x + w, y, x + w, y + h, opt) + roughLine(x + w, y + h, x, y + h, opt) + roughLine(x, y + h, x, y, opt);
}

function roughCircle(cx, cy, r, opt = {}) {
  const sw = opt.strokeWidth || 2;
  const stroke = opt.stroke || '#202020';
  const rough = opt.roughness == null ? 1.1 : opt.roughness;
  let pts = [];
  for (let i = 0; i <= 64; i++) {
    const a = (Math.PI * 2 * i) / 64;
    pts.push([cx + Math.cos(a) * (r + jitter(i + cx, rough)), cy + Math.sin(a) * (r + jitter(i + cy, rough))]);
  }
  return roughPolyline(pts, { stroke, strokeWidth: sw, roughness: rough * .6 });
}

function roughArrow(x1, y1, x2, y2, label = '') {
  const main = roughLine(x1, y1, x2, y2, { strokeWidth: 2.1, roughness: 1.1 });
  const a = Math.atan2(y2 - y1, x2 - x1);
  const len = 13;
  const h1 = roughLine(x2, y2, x2 - len * Math.cos(a - 0.45), y2 - len * Math.sin(a - 0.45), { strokeWidth: 2.1, roughness: .7 });
  const h2 = roughLine(x2, y2, x2 - len * Math.cos(a + 0.45), y2 - len * Math.sin(a + 0.45), { strokeWidth: 2.1, roughness: .7 });
    let tx = (x1 + x2) / 2 + 8;
  let ty = (y1 + y2) / 2 - 8;
  let anchor = 'middle';
  if (label) {
    if (Math.abs(y2 - y1) < Math.abs(x2 - x1)) {
      tx = x2 - 10;
      ty = y2 - 10;
      anchor = 'end';
    } else {
      tx = x2 + 10;
      ty = y2 + 16;
      anchor = 'start';
    }
  }
  return main + h1 + h2 + (label ? svgText(tx, ty, label, 16, anchor) : '');
}

function svgText(x, y, text, size = 16, anchor = 'middle') {
  return `<text x="${x}" y="${y}" font-size="${size}" text-anchor="${anchor}" font-family="KaiTi, STKaiti, SimKai, Microsoft YaHei, sans-serif" fill="#202020">${escSvg(text)}</text>`;
}

function evalExpr(expr, x) {
  let e = String(expr || '').trim();
  if (!e) return NaN;
  e = e.replace(/\^/g, '**')
    .replace(/π/g, 'Math.PI')
    .replace(/\bpi\b/gi, 'Math.PI')
    .replace(/\be\b/g, 'Math.E')
    .replace(/\bsin\b/gi, 'Math.sin')
    .replace(/\bcos\b/gi, 'Math.cos')
    .replace(/\btan\b/gi, 'Math.tan')
    .replace(/\bln\b/gi, 'Math.log')
    .replace(/\blog\b/gi, 'Math.log10')
    .replace(/\bsqrt\b/gi, 'Math.sqrt')
    .replace(/\barctan\b/gi, 'Math.atan')
    .replace(/\batan\b/gi, 'Math.atan')
    .replace(/\bexp\b/gi, 'Math.exp');
  if (!/^[0-9xX+\-*/().,\sMathPIEacosintlrqgep]+$/.test(e)) return NaN;
  try {
    return Function('x', `"use strict"; return (${e.replace(/\bX\b/g, 'x')});`)(x);
  } catch (err) {
    return NaN;
  }
}


function smoothPathD(points) {
  if (!Array.isArray(points) || points.length < 2) return '';
  if (points.length === 2) return `M ${points[0][0]} ${points[0][1]} L ${points[1][0]} ${points[1][1]}`;
  let d = `M ${points[0][0]} ${points[0][1]}`;
  for (let i = 0; i < points.length - 1; i += 1) {
    const p0 = points[i - 1] || points[i];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[i + 2] || p2;
    const cp1x = p1[0] + (p2[0] - p0[0]) / 6;
    const cp1y = p1[1] + (p2[1] - p0[1]) / 6;
    const cp2x = p2[0] - (p3[0] - p1[0]) / 6;
    const cp2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2[0]} ${p2[1]}`;
  }
  return d;
}

function roughSmoothCurve(points, opt = {}) {
  if (!Array.isArray(points) || points.length < 2) return '';
  const sw = opt.strokeWidth || 2;
  const stroke = opt.stroke || '#202020';
  const rough = opt.roughness == null ? 0.5 : opt.roughness;
  const jittered1 = points.map((p, i) => [p[0] + jitter(i + 11, rough), p[1] + jitter(i + 61, rough)]);
  const jittered2 = points.map((p, i) => [p[0] + jitter(i + 121, rough * 0.7), p[1] + jitter(i + 171, rough * 0.7)]);
  const d1 = smoothPathD(jittered1);
  const d2 = smoothPathD(jittered2);
  return `<path d="${d1}" fill="none" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" opacity="0.96"/>`
    + `<path d="${d2}" fill="none" stroke="${stroke}" stroke-width="${Math.max(1, sw * 0.72)}" stroke-linecap="round" stroke-linejoin="round" opacity="0.42"/>`;
}

function renderFunctionPlot(spec) {
  const w = spec.canvas.width, h = spec.canvas.height;
  const pad = 48;
  const [xmin, xmax] = spec.xRange;
  const [ymin, ymax] = spec.yRange;
  const sx = x => pad + (x - xmin) / (xmax - xmin) * (w - pad * 2);
  const sy = y => h - pad - (y - ymin) / (ymax - ymin) * (h - pad * 2);
  let body = '';
  if (spec.showGrid) {
    for (let i = Math.ceil(xmin); i <= Math.floor(xmax); i++) body += `<path d="M ${sx(i)} ${pad} L ${sx(i)} ${h-pad}" stroke="#e5e0d6" stroke-width="1"/>`;
    for (let j = Math.ceil(ymin); j <= Math.floor(ymax); j++) body += `<path d="M ${pad} ${sy(j)} L ${w-pad} ${sy(j)}" stroke="#e5e0d6" stroke-width="1"/>`;
  }
  if (spec.showAxes) {
    if (ymin <= 0 && ymax >= 0) body += roughArrow(pad, sy(0), w - pad + 12, sy(0), 'x');
    if (xmin <= 0 && xmax >= 0) body += roughArrow(sx(0), h - pad, sx(0), pad - 12, 'y');
  }
  (spec.curves || []).forEach(c => {
    let pts = [];
    if (Array.isArray(c.points) && c.points.length) {
      pts = c.points.map(p => Array.isArray(p) ? [sx(Number(p[0])), sy(Number(p[1]))] : [sx(Number(p.x)), sy(Number(p.y))]).filter(p => Number.isFinite(p[0]) && Number.isFinite(p[1]));
    } else if (c.expr) {
      const n = 180;
      for (let k = 0; k <= n; k++) {
        const x = xmin + (xmax - xmin) * k / n;
        const y = evalExpr(c.expr, x);
        if (Number.isFinite(y) && y > ymin - Math.abs(ymax-ymin)*2 && y < ymax + Math.abs(ymax-ymin)*2) pts.push([sx(x), sy(y)]);
        else if (pts.length > 1) { body += roughSmoothCurve(pts, { strokeWidth: 2.2, roughness: 0.42 }); pts = []; }
      }
    }
    body += roughSmoothCurve(pts, { strokeWidth: 2.2, roughness: 0.42 });
    if (c.label && pts.length) body += svgText(pts[Math.floor(pts.length * .72)][0] + 18, pts[Math.floor(pts.length * .72)][1] - 8, c.label, 15, 'start');
  });
  (spec.points || []).forEach(p => {
    body += roughCircle(sx(p.x), sy(p.y), 4, { strokeWidth: 1.8, roughness: .7 });
    if (p.label) body += svgText(sx(p.x) + 14, sy(p.y) - 8, p.label, 15, 'start');
  });
  return wrapSvg(w, h, body);
}

function pointMap(spec) {
  const map = {};
  (spec.points || []).forEach(p => { if (p.name) map[p.name] = [p.x, p.y, p.label || p.name]; });
  return map;
}

function resolvePoint(v, map) {
  if (Array.isArray(v)) return [Number(v[0]), Number(v[1])];
  if (typeof v === 'string' && map[v]) return map[v];
  if (v && typeof v === 'object') return [Number(v.x), Number(v.y), v.label || v.name || ''];
  return [NaN, NaN];
}

function renderGeometry(spec) {
  const w = spec.canvas.width, h = spec.canvas.height;
  let body = '';
  const map = pointMap(spec);
  (spec.polygons || []).forEach(poly => {
    const pts = (poly.points || poly).map(v => resolvePoint(v, map)).filter(p => Number.isFinite(p[0]) && Number.isFinite(p[1]));
    if (pts.length > 2) body += roughPolyline([...pts, pts[0]], { strokeWidth: 2, roughness: 1 });
  });
  (spec.segments || []).forEach(s => {
    const a = resolvePoint(s[0] || s.from, map), b = resolvePoint(s[1] || s.to, map);
    if (Number.isFinite(a[0]) && Number.isFinite(b[0])) body += roughLine(a[0], a[1], b[0], b[1], { strokeWidth: 2, roughness: 1 });
  });
  (spec.circles || []).forEach(c => {
    const center = resolvePoint(c.center || [c.x, c.y], map);
    const r = Number(c.r || c.radius || 40);
    if (Number.isFinite(center[0]) && Number.isFinite(r)) body += roughCircle(center[0], center[1], r, { strokeWidth: 2, roughness: 1 });
  });
  (spec.points || []).forEach(p => {
    body += roughCircle(p.x, p.y, 3.2, { strokeWidth: 1.5, roughness: .6 });
    if (p.label || p.name) body += svgText(p.x + 10, p.y - 8, p.label || p.name, 15, 'start');
  });
  (spec.annotations || []).forEach(a => {
    const p = resolvePoint(a.at || [a.x, a.y], map);
    if (Number.isFinite(p[0])) body += svgText(p[0], p[1], a.text || a.label || '', 15, 'start');
  });
  return wrapSvg(w, h, body);
}

function renderPhysics(spec) {
  const w = spec.canvas.width, h = spec.canvas.height;
  let body = '';
  (spec.objects || []).forEach(o => {
    const x = Number(o.x || 200), y = Number(o.y || 200);
    if (o.kind === 'circle' || o.kind === 'ball') body += roughCircle(x, y, Number(o.r || 28), { strokeWidth: 2, roughness: 1 });
    else if (o.kind === 'incline') {
      body += roughPolyline([[x - 120, y + 70], [x + 130, y + 70], [x + 130, y - 50], [x - 120, y + 70]], { strokeWidth: 2, roughness: 1 });
    } else {
      body += roughRect(x - 34, y - 24, Number(o.w || 68), Number(o.h || 48), { strokeWidth: 2, roughness: 1 });
    }
    if (o.label) body += svgText(x, y + 5, o.label, 16);
  });
  (spec.forces || []).forEach(f => {
    const a = Array.isArray(f.from) ? f.from : [Number(f.x || 0), Number(f.y || 0)];
    const b = Array.isArray(f.to) ? f.to : [Number(f.x2 || 0), Number(f.y2 || 0)];
    if (Number.isFinite(a[0]) && Number.isFinite(b[0])) body += roughArrow(a[0], a[1], b[0], b[1], f.label || '');
  });
  (spec.annotations || []).forEach(a => body += svgText(Number(a.x || 40), Number(a.y || 40), a.text || a.label || '', 15, 'start'));
  return wrapSvg(w, h, body);
}

function renderFlowchart(spec) {
  const w = spec.canvas.width, h = spec.canvas.height;
  let body = '';
  const nodes = {};
  (spec.nodes || []).forEach((n, i) => {
    const x = Number(n.x || (w / 2)), y = Number(n.y || (70 + i * 86)), ww = Number(n.w || 150), hh = Number(n.h || 42);
    nodes[n.id || n.name || String(i)] = { x, y, w: ww, h: hh, label: n.label || n.text || n.name || '' };
    body += roughRect(x - ww / 2, y - hh / 2, ww, hh, { strokeWidth: 2, roughness: 1 });
    body += svgText(x, y + 5, n.label || n.text || n.name || '', 15);
  });
  (spec.edges || []).forEach(e => {
    const a = nodes[e.from] || nodes[e[0]], b = nodes[e.to] || nodes[e[1]];
    if (a && b) body += roughArrow(a.x, a.y + a.h / 2, b.x, b.y - b.h / 2, e.label || '');
  });
  return wrapSvg(w, h, body);
}

function wrapSvg(w, h, body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" class="sukoya-diagram" role="img">${body}</svg>`;
}

function renderDiagramSpec(spec) {
  const s = normalizeDiagramSpec(spec);
  if (s.type === 'function_plot') return renderFunctionPlot(s);
  if (s.type === 'physics') return renderPhysics(s);
  if (s.type === 'flowchart') return renderFlowchart(s);
  if (s.type === 'none') return wrapSvg(520, 260, svgText(40, 120, s.reason || '这题不需要画图', 18, 'start'));
  return renderGeometry(s);
}

function createFallbackDiagramSpec(text) {
  const s = String(text || '');
  if (/偏导|∂|二阶偏导|证明|\partial/.test(s)) {
    return normalizeDiagramSpec({ type: 'none', title: '本题一般不需要图示', reason: '本题以公式推导为主，可不画图。' });
  }
  if (/z\s*=\s*6\s*[-−]\s*2x\^?2\s*[-−]\s*2y\^?2|z\s*=\s*6\s*[-−]\s*2x²\s*[-−]\s*2y²|旋转抛物面|曲面/.test(s)) {
    return normalizeDiagramSpec({
      type: 'function_plot',
      title: '曲面截面示意',
      xRange: [-2.4, 2.4],
      yRange: [-0.8, 6.6],
      showAxes: true,
      showGrid: false,
      curves: [{ expr: '6-2*(x**2)', label: '' }],
      points: [{ x: 0, y: 6, label: '顶点' }]
    });
  }
  if (/抛物线|x\^?2|x²|函数|图像|曲线/.test(s)) {
    return normalizeDiagramSpec({
      type: 'function_plot',
      title: '函数图像',
      xRange: [-4, 4],
      yRange: [-3, 8],
      showAxes: true,
      showGrid: false,
      curves: [{ expr: 'x**2', label: '' }],
      points: [{ x: 0, y: 0, label: 'O' }]
    });
  }
  if (/直线|平面|空间|方程|交点|相交|平行/.test(s)) {
    return normalizeDiagramSpec({
      type: 'geometry',
      title: '空间几何示意',
      points: [
        { name: 'O', x: 120, y: 300 },
        { name: 'X', x: 260, y: 300, label: 'x' },
        { name: 'Y', x: 70, y: 220, label: 'y' },
        { name: 'Z', x: 120, y: 120, label: 'z' },
        { name: 'A', x: 220, y: 250 },
        { name: 'B', x: 360, y: 180 }
      ],
      segments: [['O','X'],['O','Y'],['O','Z'],['A','B']],
      polygons: [[{x:210,y:140},{x:470,y:190},{x:380,y:320},{x:140,y:270}]],
      annotations: [
        { x: 405, y: 170, text: 'α' },
        { x: 290, y: 210, text: 'l' }
      ]
    });
  }
  if (/圆|半径|直径/.test(s)) {
    return normalizeDiagramSpec({
      type: 'geometry',
      title: '圆形示意',
      points: [{ name: 'O', x: 300, y: 210 }, { name: 'A', x: 390, y: 210 }],
      circles: [{ center: 'O', r: 90 }],
      segments: [['O','A']],
      annotations: [{ x: 335, y: 195, text: 'r' }]
    });
  }
  if (/受力|斜面|重力|mg|弹力|摩擦/.test(s)) {
    return normalizeDiagramSpec({
      type: 'physics',
      title: '受力示意图',
      objects: [{ kind: 'block', x: 330, y: 210, label: 'm' }],
      forces: [
        { from: [330, 210], to: [330, 120], label: 'N' },
        { from: [330, 210], to: [330, 320], label: 'mg' },
        { from: [330, 210], to: [255, 210], label: 'f' }
      ]
    });
  }
  return normalizeDiagramSpec({
    type: 'geometry',
    title: '三角形示意',
    points: [
      { name: 'A', x: 150, y: 130 },
      { name: 'B', x: 450, y: 130 },
      { name: 'C', x: 300, y: 300 }
    ],
    segments: [['A', 'B'], ['B', 'C'], ['C', 'A']]
  });
}

function downloadTextFile(name, content, type = 'text/plain') {
  const blob = new Blob([content], { type });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 400);
}

export default {
  name: 'SukoyaHomeworkApp',
  data() {
    return {
      rawText: localStorage.getItem('sukoya_raw_text') || '',
      answerText: localStorage.getItem('sukoya_answer_text') || '',
      answerEditing: false,
      editableAnswerText: '',
      uploadedName: '',
      fonts: [],
      settings: {
        font_option: '', font_size: 31, line_spacing: 52,
        width: 794, height: 1123, left_margin: 72, top_margin: 74, right_margin: 60, bottom_margin: 60, word_spacing: 0.8, handwriting_chaos: 60, ink_bleed_count: 0, handwriting_profile: 'sukoya',
      },
      paperMode: 'line',
      insertDiagramInHandwriting: true,
      previewImages: [],
      working: false,
      loadingAi: false,
      message: '',
      keyStatus: { has_key: false, masked: '', model: 'deepseek-chat' },
      apiKeyInput: '',
      modelInput: localStorage.getItem('sukoya_model') || 'deepseek-chat',
      keyMessage: '',
      showKeyModal: true,
      cacheOpen: false,
      cacheKeyword: '',
      cacheItems: loadCacheItems(),
      diagramOpen: false,
      diagramSpec: null,
      diagramSvg: '',
      diagramTitle: '',
      diagramPngData: '', 
    };
  },
  computed: {
    answerPreviewText() { return toHandwritingFriendly(this.answerText || ''); },
    handwritingText() { return toHandwritingFriendly(this.answerText || this.rawText); },
    chaosLabel() {
      const v = Number(this.settings.handwriting_chaos || 0);
      if (v <= 25) return '工整';
      if (v <= 60) return '自然';
      return '偏乱';
    },
    bleedLabel() {
      const v = Number(this.settings.ink_bleed_count || 0);
      if (v <= 0) return '干净';
      if (v === 1) return '轻微';
      if (v === 2) return '中等';
      return '明显';
    },
    filteredCacheItems() {
      const key = this.cacheKeyword.trim().toLowerCase();
      if (!key) return this.cacheItems;
      return this.cacheItems.filter(item => `${item.title} ${item.preview} ${item.rawText} ${item.answerText}`.toLowerCase().includes(key));
    }
  },
  watch: {
    rawText(v) { localStorage.setItem('sukoya_raw_text', v); },
    answerText(v) { localStorage.setItem('sukoya_answer_text', v); },
    modelInput(v) { localStorage.setItem('sukoya_model', v); }
  },
  async mounted() {
    await this.loadFonts();
    await this.checkKey();
    if (!this.keyStatus.has_key) this.showKeyModal = true;
  },
  methods: {
    forceKeyModal() { this.keyMessage = ''; this.showKeyModal = true; },
    displayFontName(name) {
      if (name === '__system__:auto') return '系统字体（兜底）';
      if (name === '__profile__:seuomi') return 'seuomi（样本档案）';
      if (/^seuomi\.(ttf|otf)$/i.test(name)) return 'seuomi';
      if (/^sukoya\.(ttf|otf)$/i.test(name)) return 'sukoya';
      return name.replace(/^font_/, '').replace(/\.ttf$|\.otf$/i, '');
    },
    async loadFonts() {
      try {
        const res = await fetch('/api/fonts_info');
        const data = await readJson(res);
        if (Array.isArray(data) && data.length) {
          const list = [...data];
          if (!list.some(f => /^seuomi\.(ttf|otf)$/i.test(f)) && !list.includes('__profile__:seuomi')) {
            list.push('__profile__:seuomi');
          }
          this.fonts = list;
          this.settings.font_option = list.find(f => /^sukoya\.(ttf|otf)$/i.test(f)) || list.find(f => f !== '__system__:auto') || '__system__:auto';
          this.syncProfileFont();
          return;
        }
        this.fonts = ['__system__:auto'];
        this.settings.font_option = '__system__:auto';
        this.message = '未找到自定义字体，已临时使用系统字体。把 sukoya.ttf 放进 ttf_files 后重启即可优先使用。';
      } catch (error) {
        this.fonts = ['__system__:auto'];
        this.settings.font_option = '__system__:auto';
        this.message = '字体列表读取失败，已临时使用系统字体。';
      }
    },
    syncFontProfile() {
      const font = this.settings.font_option || '';
      if (font === '__profile__:seuomi' || /^seuomi\.(ttf|otf)$/i.test(font)) {
        this.settings.handwriting_profile = 'seuomi';
      } else if (/^sukoya\.(ttf|otf)$/i.test(font)) {
        this.settings.handwriting_profile = 'sukoya';
      }
    },

    syncProfileFont() {
      const profile = this.settings.handwriting_profile || 'sukoya';
      const preferred = profile === 'seuomi'
        ? (this.fonts.find(f => /^seuomi\.(ttf|otf)$/i.test(f)) || this.fonts.find(f => f === '__profile__:seuomi'))
        : this.fonts.find(f => /^sukoya\.(ttf|otf)$/i.test(f));
      if (preferred) this.settings.font_option = preferred;
    },

    async uploadPersonalFont(event) {
      const file = event.target.files && event.target.files[0];
      if (!file) return;
      const form = new FormData();
      form.append('font_file', file);
      form.append('handwriting_profile', this.settings.handwriting_profile || 'sukoya');
      try {
        this.message = '正在导入字体...';
        const res = await fetch('/api/upload_font', { method: 'POST', body: form });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || '字体导入失败');
        this.fonts = Array.isArray(data.fonts) ? data.fonts : [];
        this.settings.font_option = data.filename || this.fonts.find(f => /^sukoya\.(ttf|otf)$/i.test(f)) || this.fonts[0] || '__system__:auto';
        this.message = `字体已导入到 ${this.settings.handwriting_profile || 'sukoya'}，不会覆盖其他书写体。`;
      } catch (error) {
        this.message = error.message || '字体导入失败。';
      } finally {
        event.target.value = '';
      }
    },

    async checkKey() {
      try {
        const res = await fetch('/api/deepseek_key_status');
        const data = await readJson(res);
        this.keyStatus = data;
        if (this.keyStatus.model) this.modelInput = this.keyStatus.model;
      } catch (error) {
        this.keyStatus = { has_key: false, masked: '', model: 'deepseek-chat' };
        this.message = error.message || '后端未连接。';
      }
    },
    async saveApiKey(closeAfterSave = true) {
      this.keyMessage = '';
      const key = this.apiKeyInput.trim();
      if (!key && !this.keyStatus.has_key) {
        this.keyMessage = '请填写真实 DeepSeek API Key。';
        return;
      }
      if (!key && this.keyStatus.has_key) {
        this.showKeyModal = closeAfterSave ? false : this.showKeyModal;
        return;
      }
      if (!/^sk-[A-Za-z0-9_\-]{10,}/.test(key)) {
        this.keyMessage = 'API Key 格式不对，一般以 sk- 开头。';
        return;
      }
      try {
        const res = await fetch('/api/deepseek_save_key', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ api_key: key, model: this.modelInput }) });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || '保存失败');
        this.keyStatus = { has_key: true, masked: data.masked, model: data.model || this.modelInput };
        this.apiKeyInput = '';
        if (closeAfterSave) this.showKeyModal = false;
      } catch (error) {
        this.keyMessage = error.message || '保存失败。';
      }
    },
    async clearApiKey() {
      try {
        const res = await fetch('/api/deepseek_clear_key', { method: 'POST' });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || '清除失败');
        this.keyStatus = { has_key: false, masked: '', model: 'deepseek-chat' };
        this.apiKeyInput = '';
        this.keyMessage = '';
        this.showKeyModal = true;
        this.message = '本地 Key 已清除。';
      } catch (error) {
        this.keyMessage = error.message || '清除失败。';
      }
    },

    requireKey() {
      if (!this.keyStatus.has_key) { this.showKeyModal = true; this.message = '请先接入 DeepSeek API。'; return false; }
      return true;
    },
    async handleDrop(e) {
      const file = e.dataTransfer.files && e.dataTransfer.files[0];
      if (file) await this.extractFile(file);
    },
    async handleFileChange(e) {
      const file = e.target.files && e.target.files[0];
      if (file) await this.extractFile(file);
      e.target.value = '';
    },
    async extractFile(file) {
      this.uploadedName = file.name;
      this.message = '正在读取文件...';
      const form = new FormData();
      form.append('file', file);
      try {
        const res = await fetch('/api/upload_extract', { method: 'POST', body: form });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || '文件读取失败');
        this.rawText = data.text || '';
        this.message = data.kind === 'image' ? '图片已处理，识别不完整就在左侧补一下。' : '文件内容已读取。';
        this.saveCurrentToCache(false);
      } catch (error) {
        this.message = error.message || '文件读取失败。';
      }
    },
    startAnswerEdit() {
      this.editableAnswerText = this.answerText || '';
      this.answerEditing = true;
      this.message = '可以修改答案，点“结束更改”后再生成手写版。';
    },
    finishAnswerEdit() {
      this.answerText = normalizeAnswerText(this.editableAnswerText || '');
      this.editableAnswerText = this.answerText;
      this.answerEditing = false;
      this.saveCurrentToCache(false);
      this.message = '修改已保存，手写版会使用当前答案。';
    },
    cancelAnswerEdit() {
      this.editableAnswerText = this.answerText || '';
      this.answerEditing = false;
      this.message = '已取消本次修改。';
    },

    async aiAction(mode) {
      if (!this.requireKey()) return;
      const source = (this.rawText || this.answerText || '').trim();
      if (!source) { this.message = '先输入题目或上传文件。'; return; }
      this.loadingAi = true;
      this.message = this.modelInput === 'deepseek-reasoner' ? 'DeepSeek 正在处理...' : 'DeepSeek 正在生成...';
      const baseRule = '只输出能直接写进作业本的内容。答案中短，像普通学生写作业，不像讲课，不要自我检查。不要写答题思路、正式答案、最终答案、参考答案、解析、总结。不要 Markdown。禁止出现反问、疑问句、自我纠错或核验过程：不要写“检查”“验算”“确实”“原点在平面？”“无交点？检查”。公式要保持数学书写感：分数优先写成 3/2、5/3 这种可被系统转成分数样式的格式；不要写小数。乘号统一写成 x，不要写 ·、×、cdot、times。可以用简单 LaTeX 语义，但不要输出源码块；不要写 \begin、\end、\cdot、\neq、\leq、\geq、\times、\;。这些要直接写成分行方程、x、≠、≤、≥。矩阵和行列式直接分行写，不要源码。每题一般写3到6行，保留关键式子、必要步骤和结果；如果有多题，保留原题号逐题回答。';
      const prompts = {
        answer: `${baseRule} 根据题目直接给必要步骤和结果。`,
        multi: `${baseRule} 按题号逐题回答，题号不要丢，每题尽量控制在几行。`,
        steps: `${baseRule} 只补缺少的关键步骤，不要展开太多。`,
        formula: `${baseRule} 整理必要公式，分数、根号、积分等写成人类可读格式。`,
        natural: `${baseRule} 把内容改得更像学生随手写的作业，别太工整。`,
        search: `${baseRule} 需要核对资料时只给可写进作业的简短结论，不编造来源。`
      };
      try {
        const res = await fetch('/api/deepseek_polish', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: source, instruction: prompts[mode], model: this.modelInput })
        });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || 'DeepSeek 调用失败');
        this.answerText = normalizeAnswerText(data.text || '');
        this.editableAnswerText = this.answerText;
        this.answerEditing = false;
        this.message = '答案已生成。';
        this.saveCurrentToCache(false);
      } catch (error) {
        this.message = error.message || 'DeepSeek 调用失败。';
        if (String(this.message).includes('API')) this.showKeyModal = true;
      } finally {
        this.loadingAi = false;
      }
    },

    async generateDiagram() {
      const source = `${this.rawText || ''}\n\n${this.answerText || ''}`.trim();
      if (!source) { this.message = '先输入题目或生成答案。'; return; }

      // 先立即生成一张本地兜底图，避免界面空白。
      const fallback = createFallbackDiagramSpec(source);
      this.diagramSpec = fallback;
      this.diagramTitle = fallback.title || '图示';
      this.diagramSvg = renderDiagramSpec(fallback);
      this.diagramOpen = true;
      this.message = '已先生成本地图示，正在尝试让 DeepSeek 优化...';

      if (!this.requireKey()) {
        this.message = '已生成本地图示。填写 DeepSeek Key 后可优化图示。';
        return;
      }

      this.loadingAi = true;
      const instruction = `你是 SukoyaDraw 结构化画图规划助手。只输出合法 JSON，不要 Markdown，不要解释。
目标：生成适合学生作业本插图的“干净图像”，只保留必要图形，不要说明文字堆砌。
只允许以下 type: function_plot, geometry, physics, flowchart, none。
除非题目完全不需要图，否则不要返回 none。
强限制：
1. 图内禁止大段中文说明。
2. 最多只保留少量必要标签，例如 O、x、y、z、A、B、r、顶点。
3. 优先画坐标轴、曲线、圆、线段、受力箭头，不要画说明框，不要给曲线写公式标签。
4. 如果是函数、曲线、曲面、抛物线、圆锥曲线、旋转曲面、几何图像题，优先返回 function_plot 或 geometry 的简洁图。
5. function_plot 中 showGrid 默认 false，showAxes 默认 true；曲线尽量少，通常 1 条即可。
通用字段：{"type":"","title":"","canvas":{"width":680,"height":420},"style":"handwriting"}。
function_plot 字段：xRange, yRange, showAxes, showGrid, curves:[{"expr":"x**2","label":""}], points:[{"x":0,"y":0,"label":"O"}]。表达式用简单写法，例如 x**2、sin(x)、sqrt(x)。
geometry 字段：points:[{"name":"A","x":120,"y":120}], segments:[["A","B"]], circles:[{"center":"O","r":60}], polygons:[["A","B","C"]], annotations:[{"x":80,"y":80,"text":"x"}]。
physics 字段：objects:[{"kind":"block","x":320,"y":220,"label":"m"}], forces:[{"from":[320,220],"to":[320,120],"label":"N"}]。
flowchart 字段：nodes:[{"id":"a","x":340,"y":80,"label":"开始"}], edges:[{"from":"a","to":"b","label":""}]。
坐标单位是 SVG 像素，x 向右，y 向下。图要简洁、平滑、留白充足。`;
      try {
        const res = await fetch('/api/deepseek_polish', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: source, instruction, model: this.modelInput })
        });
        const data = await readJson(res);
        if (!res.ok) throw new Error(data.error || '图示生成失败');

        const parsed = extractJsonObject(data.text);
        let spec = normalizeDiagramSpec(parsed || fallback);
        if (spec.type === 'none') spec = fallback;

        this.diagramSpec = spec;
        this.diagramTitle = spec.title || '图示';
        this.diagramSvg = renderDiagramSpec(spec);
        this.diagramOpen = true;
        this.message = '图示已生成。';
      } catch (error) {
        this.diagramSpec = fallback;
        this.diagramTitle = fallback.title || '图示';
        this.diagramSvg = renderDiagramSpec(fallback);
        this.diagramOpen = true;
        this.message = 'DeepSeek 图示优化失败，已保留本地图示。';
      } finally {
        this.loadingAi = false;
      }
    },
    makeLocalDiagram() {
      const source = `${this.rawText || ''}\n\n${this.answerText || ''}`.trim() || '画一个三角形示意图';
      const spec = createFallbackDiagramSpec(source);
      this.diagramSpec = spec;
      this.diagramTitle = spec.title || '图示';
      this.diagramSvg = renderDiagramSpec(spec);
      this.diagramOpen = true;
      this.message = '本地测试图已生成。';
    },
    insertDiagramNote() {
      if (!this.diagramSvg) return;
      const title = this.diagramTitle || '图示';
      const note = `\n\n【图示：${title}】`;
      if (!this.answerText.includes(note.trim())) {
        this.answerText = (this.answerText || '').trim() + note;
      }
      this.message = '图示标记已插入答案，图像可单独导出。';
    },
    downloadDiagramSvg() {
      if (!this.diagramSvg) return;
      downloadTextFile(`sukoya_diagram_${Date.now()}.svg`, this.diagramSvg, 'image/svg+xml;charset=utf-8');
    },
    downloadDiagramPng() {
      if (!this.diagramSvg) return;
      const svg = this.diagramSvg;
      const img = new Image();
      const blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      img.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = img.naturalWidth || 680;
        canvas.height = img.naturalHeight || 420;
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0);
        canvas.toBlob(pngBlob => {
          if (!pngBlob) return;
          const a = document.createElement('a');
          a.href = URL.createObjectURL(pngBlob);
          a.download = `sukoya_diagram_${Date.now()}.png`;
          document.body.appendChild(a);
          a.click();
          setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 400);
        }, 'image/png');
        URL.revokeObjectURL(url);
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        this.message = 'PNG 导出失败，可先导出 SVG。';
      };
      img.src = url;
    },
    async diagramSvgToPngBase64() {
      if (!this.diagramSvg) return '';
      return new Promise(resolve => {
        try {
          const svgBlob = new Blob([this.diagramSvg], { type: 'image/svg+xml;charset=utf-8' });
          const url = URL.createObjectURL(svgBlob);
          const img = new Image();
          img.onload = () => {
            try {
              const canvas = document.createElement('canvas');
              const w = Math.max(640, img.width || 680);
              const h = Math.max(360, img.height || 420);
              canvas.width = w;
              canvas.height = h;
              const ctx = canvas.getContext('2d');
              ctx.clearRect(0, 0, w, h);
              ctx.drawImage(img, 0, 0, w, h);
              const data = canvas.toDataURL('image/png');
              URL.revokeObjectURL(url);
              resolve(data.split(',')[1] || '');
            } catch (e) {
              URL.revokeObjectURL(url);
              resolve('');
            }
          };
          img.onerror = () => { URL.revokeObjectURL(url); resolve(''); };
          img.src = url;
        } catch (e) { resolve(''); }
      });
    },
    clearDiagram() {
      this.diagramSpec = null;
      this.diagramSvg = '';
      this.diagramTitle = '';
      this.diagramPngData = '';
      this.diagramOpen = false;
      this.message = '图示已清空。';
    },

    async buildForm({ pdf = false } = {}) {
      const form = new FormData();
      const diagramPngBase64 = (this.insertDiagramInHandwriting && this.diagramSvg) ? await this.diagramSvgToPngBase64() : '';
      const values = {
        text: this.handwritingText,
        font_size: String(this.settings.font_size), line_spacing: String(this.settings.line_spacing), fill: '(20, 22, 25)',
        left_margin: String(this.settings.left_margin), top_margin: String(this.settings.top_margin), right_margin: String(this.settings.right_margin), bottom_margin: String(this.settings.bottom_margin),
        word_spacing: String(this.settings.word_spacing), line_spacing_sigma: '0.6', font_size_sigma: '1.2', word_spacing_sigma: '2.2', perturb_x_sigma: '0.8', perturb_y_sigma: '2.0', perturb_theta_sigma: '0.018',
        strikethrough_probability: '0', strikethrough_length_sigma: '0', strikethrough_width_sigma: '0', strikethrough_angle_sigma: '0', strikethrough_width: '0', ink_depth_sigma: '1.35',
        width: String(this.settings.width), height: String(this.settings.height), isUnderlined: this.paperMode === 'line' ? 'true' : 'false', enableEnglishSpacing: 'false',
        font_option: this.settings.font_option, preview: pdf ? 'false' : 'true', pdf_save: pdf ? 'true' : 'false', full_preview: 'true',
        embed_diagram: diagramPngBase64 ? 'true' : 'false', diagram_png_base64: diagramPngBase64, diagram_caption: '', use_sukoya_optimized_renderer: 'true', handwriting_chaos: String(this.settings.handwriting_chaos || 60), ink_bleed_count: String(this.settings.ink_bleed_count || 0), handwriting_profile: this.settings.handwriting_profile || 'sukoya'
      };
      Object.entries(values).forEach(([k, v]) => form.append(k, v));
      return form;
    },
    async submitGeneration({ pdf = false } = {}) {
      const res = await fetch('/api/generate_handwriting', { method: 'POST', body: await this.buildForm({ pdf }) });
      const data = await readJson(res);
      if (!res.ok || !data.task_id) throw new Error(data.message || data.error || '生成任务创建失败');
      return data.task_id;
    },
    async waitForTask(taskId) {
      for (let i = 0; i < 180; i += 1) {
        const res = await fetch(`/api/generate_handwriting/task/${taskId}`);
        const data = await readJson(res);
        this.message = data.task_message || data.message || '正在生成...';
        if (data.task_status === 'completed' || data.status === 'completed') return;
        if (data.task_status === 'failed' || data.status === 'failed') throw new Error(data.error_message || data.message || '生成失败');
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      throw new Error('生成超时，请减少内容后重试。');
    },
    async generatePreview() {
      if (this.answerEditing) this.finishAnswerEdit();
      if (!this.settings.font_option) this.settings.font_option = '__system__:auto';
      if (!this.handwritingText.trim()) { this.message = '先生成或输入答案。'; return; }
      if (this.insertDiagramInHandwriting && !this.diagramSvg && /图|画|曲面|函数|直线|平面|受力|示意|坐标|圆/.test(`${this.rawText}\n${this.answerText}`)) {
        this.makeLocalDiagram();
      }
      this.working = true; this.previewImages = [];
      this.message = (this.insertDiagramInHandwriting && this.diagramSvg) ? '正在生成手写答案并插入图示...' : '正在生成手写答案...';
      try {
        const taskId = await this.submitGeneration({ pdf: false });
        await this.waitForTask(taskId);
        const result = await fetch(`/api/generate_handwriting/task/${taskId}/result`);
        const data = await readJson(result);
        if (!result.ok) throw new Error(data.message || data.error || '结果读取失败');
        this.previewImages = (data.images || []).map(b64 => `data:image/png;base64,${b64}`);
        this.message = `手写答案已生成，共 ${this.previewImages.length} 页。`;
        this.saveCurrentToCache(false);
      } catch (error) {
        this.message = error.message || '生成失败。';
      } finally {
        this.working = false;
      }
    },
    async downloadPdf() {
      if (this.answerEditing) this.finishAnswerEdit();
      if (!this.handwritingText.trim()) { this.message = '先生成或输入答案。'; return; }
      if (this.insertDiagramInHandwriting && !this.diagramSvg && /图|画|曲面|函数|直线|平面|受力|示意|坐标|圆/.test(`${this.rawText}\n${this.answerText}`)) {
        this.makeLocalDiagram();
      }
      this.working = true;
      this.message = (this.insertDiagramInHandwriting && this.diagramSvg) ? '正在导出含图 PDF...' : '正在导出 PDF...';
      try {
        const taskId = await this.submitGeneration({ pdf: true });
        await this.waitForTask(taskId);
        const result = await fetch(`/api/generate_handwriting/task/${taskId}/result`);
        if (!result.ok) throw new Error('PDF 读取失败');
        const blob = await result.blob();
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a'); a.href = url; a.download = 'sukoya_handwriting.pdf'; a.click(); URL.revokeObjectURL(url);
        this.message = 'PDF 已导出。';
        this.saveCurrentToCache(false);
      } catch (error) {
        this.message = error.message || 'PDF 导出失败。';
      } finally {
        this.working = false;
      }
    },
    async copyAnswer() {
      await navigator.clipboard.writeText(this.answerText || this.rawText);
      this.message = '已复制。';
    },
    saveCurrentToCache(showMessage = true) {
      const raw = (this.rawText || '').trim();
      const ans = (this.answerText || '').trim();
      if (!raw && !ans) {
        if (showMessage) this.message = '没有可缓存的内容。';
        return;
      }
      const id = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const main = raw || ans;
      const preview = toHandwritingFriendly(ans || raw).replace(/\s+/g, ' ').slice(0, 90);
      const item = {
        id,
        title: shortTitle(main),
        time: nowText(),
        rawText: raw,
        answerText: ans,
        uploadedName: this.uploadedName || '',
        preview,
        answerLength: ans.length,
      };
      const sameKey = `${raw}\n---\n${ans}`;
      const old = this.cacheItems.filter(v => `${v.rawText}\n---\n${v.answerText}` !== sameKey);
      this.cacheItems = [item, ...old].slice(0, 60);
      saveCacheItems(this.cacheItems);
      if (showMessage) this.message = '已存入缓存库。';
    },
    restoreCache(item) {
      this.rawText = item.rawText || '';
      this.answerText = item.answerText || '';
      this.uploadedName = item.uploadedName || '';
      this.previewImages = [];
      this.cacheOpen = false;
      this.message = '已打开缓存。';
    },
    deleteCache(id) {
      this.cacheItems = this.cacheItems.filter(item => item.id !== id);
      saveCacheItems(this.cacheItems);
      this.message = '已删除缓存。';
    },
    async clearAllCache() {
      this.cacheItems = [];
      saveCacheItems(this.cacheItems);
      this.clearCurrentCache(false);
      try {
        if (window.caches) {
          const keys = await window.caches.keys();
          await Promise.all(keys.map(key => window.caches.delete(key)));
        }
        if (navigator.serviceWorker) {
          const regs = await navigator.serviceWorker.getRegistrations();
          await Promise.all(regs.map(reg => reg.unregister()));
        }
      } catch (error) {
        console.warn(error);
      }
      try {
        await fetch('/api/clear_runtime_cache', { method: 'POST' });
      } catch (error) {
        console.warn(error);
      }
      this.message = '缓存已清理。';
    },
    clearCurrentCache(showMessage = true) {
      this.rawText = '';
      this.answerText = '';
      this.uploadedName = '';
      this.previewImages = [];
      localStorage.removeItem('sukoya_raw_text');
      localStorage.removeItem('sukoya_answer_text');
      if (showMessage) this.message = '当前内容已清空。';
    }
  }
};
</script>

<style>
*{box-sizing:border-box} body{margin:0;background:#f5f8ff;color:#172033;font-family:"Microsoft YaHei","PingFang SC",Arial,sans-serif} button,input,textarea,select{font:inherit} button{border:0;border-radius:12px;padding:10px 14px;background:#eaf2ff;color:#1556b3;cursor:pointer} button:hover{filter:brightness(.98)} button:disabled{opacity:.55;cursor:not-allowed}.primary{background:#2f72ff;color:white;box-shadow:0 8px 18px rgba(47,114,255,.22)}.light{background:white;border:1px solid #d9e6ff}.small{padding:7px 10px;border-radius:10px;font-size:13px}.danger{color:#c43434;background:#fff0f0}.full{width:100%;margin-top:14px}.app-shell{min-height:100vh;padding:22px}.topbar{max-width:1380px;margin:0 auto 16px;display:flex;justify-content:space-between;align-items:center;gap:18px}.topbar h1{margin:0;font-size:28px;color:#102a5c}.topbar p{margin:8px 0 0;color:#64738b}.layout{--panel-h:calc(100vh - 132px);max-width:1380px;margin:0 auto;display:grid;grid-template-columns:minmax(320px,.92fr) minmax(430px,1.08fr) 270px;gap:16px;align-items:stretch}.panel-card{height:var(--panel-h);min-height:620px;max-height:860px}.center-stack{display:flex;flex-direction:column;gap:16px;min-height:0}.card{background:rgba(255,255,255,.94);border:1px solid #dbe8ff;border-radius:22px;box-shadow:0 16px 38px rgba(45,93,162,.10);padding:18px}.input-card,.tools-card,.half-card{display:flex;flex-direction:column;min-height:0}.half-card{flex:1 1 0;height:calc((var(--panel-h) - 16px)/2);min-height:0}.third-card{flex:1 1 0;height:calc((var(--panel-h) - 32px)/3);min-height:220px}.mini-tip{margin-top:8px;color:#7a879b;font-size:12px;line-height:1.4}.card-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;flex:0 0 auto}.card h2{margin:0;color:#15366f;font-size:19px}.card-head span{color:#789; font-size:13px}.upload-box{border:1px dashed #9bbcff;background:#f9fbff;border-radius:16px;padding:12px;margin-bottom:12px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;flex:0 0 auto}.upload-box span{color:#687891;font-size:13px}textarea{width:100%;flex:1 1 auto;min-height:0;resize:none;border:1px solid #d6e3fa;border-radius:16px;padding:15px;outline:none;line-height:1.75;background:#fbfdff;overflow:auto}textarea:focus,input:focus,select:focus{border-color:#78a8ff;box-shadow:0 0 0 4px rgba(47,114,255,.10);outline:none}.answer-preview{flex:1 1 auto;min-height:0;overflow:auto;border-radius:16px;background:#f9fbff;border:1px solid #e1ebff;padding:16px;line-height:1.9;white-space:normal}.single-preview{font-size:16px}.answer-pre{margin:0;white-space:pre-wrap;word-break:break-word;font:inherit;line-height:1.9;color:#172033}.diagram-panel{margin-top:12px;border:1px solid #e1ebff;background:#fbfdff;border-radius:16px;padding:12px;flex:0 0 auto}.diagram-head{display:flex;justify-content:space-between;align-items:center;color:#15366f;font-size:14px;margin-bottom:10px}.diagram-head span{font-size:12px;color:#7a879b}.diagram-canvas{width:100%;overflow:auto;text-align:center;border-radius:12px;background:#fffdf8;border:1px solid #edf2ff;padding:10px;min-height:200px;display:flex;align-items:center;justify-content:center}.diagram-canvas svg{max-width:100%;height:auto;display:block;margin:0 auto}.diagram-panel-fixed{flex:1 1 auto;min-height:0;overflow:auto;border-radius:16px;background:#f9fbff;border:1px solid #e1ebff;padding:12px}.diagram-card{display:flex;flex-direction:column;min-height:0}.diagram-empty{min-height:130px;display:grid;place-items:center;color:#8291aa;background:#f9fbff;border:1px dashed #d7e5ff;border-radius:12px}.sukoya-diagram text{paint-order:stroke;stroke:#fffdf8;stroke-width:3px;stroke-linejoin:round}.text-line{margin:0 0 5px}.latex-line{margin:6px 0;padding:7px 9px;background:#fff;border:1px solid #e8eefc;border-radius:10px;overflow-x:auto}.latex-preview-item{margin:0 0 10px;padding:10px 12px;background:#fff;border:1px solid #e8eefc;border-radius:12px;overflow-x:auto}.latex-inline{display:inline-flex;align-items:center;vertical-align:middle;margin:0 3px;font-family:'Times New Roman','Cambria Math',serif;font-size:1.05em}.latex-block{display:flex;justify-content:center;align-items:center;margin:8px 0;font-family:'Times New Roman','Cambria Math',serif;font-size:1.12em}.frac{display:inline-flex;flex-direction:column;align-items:center;vertical-align:middle;line-height:1.05;margin:0 3px}.frac-top{border-bottom:1.5px solid currentColor;padding:0 5px 2px}.frac-bottom{padding:2px 5px 0}.sqrt{display:inline-flex;align-items:flex-start;margin:0 2px}.sqrt-body{border-top:1.5px solid currentColor;padding:0 3px;margin-left:1px}.matrix-wrap{display:inline-flex;align-items:center;gap:3px}.matrix-bracket{font-size:2.2em;line-height:1}.matrix-table{border-collapse:separate;border-spacing:10px 4px}.matrix-table td{text-align:center;white-space:nowrap}sup,sub{font-size:.72em;line-height:0}.formula-pane .empty-text{line-height:1.8}.empty-text{color:#8291aa}.image-preview{flex:1 1 auto;min-height:0;border-radius:16px;background:#f9fbff;border:1px solid #e1ebff;padding:14px;text-align:center;overflow:auto}.image-preview img{width:100%;max-width:794px;display:block;margin:0 auto 16px;border-radius:10px;border:1px solid #d7e5ff;box-shadow:0 12px 28px rgba(45,93,162,.12);background:white}.empty{height:100%;min-height:180px;display:grid;place-items:center;color:#8291aa}.tools-card{position:sticky;top:18px;gap:10px;overflow:auto}.tools-card label,.modal-label{display:flex;flex-direction:column;gap:6px;color:#4d607d;font-size:13px}input,select{width:100%;border:1px solid #d6e3fa;border-radius:12px;padding:9px 10px;background:white}.divider{height:1px;background:#e1ebff;margin:4px 0;flex:0 0 auto}.msg{margin:6px 0 0;color:#365b99;font-size:13px;line-height:1.5}.msg.error{color:#c93636}.modal-mask{position:fixed;inset:0;background:rgba(15,31,57,.50);display:grid;place-items:center;padding:20px;z-index:20}.modal-card{width:min(460px,100%);background:white;border-radius:22px;padding:24px;box-shadow:0 24px 70px rgba(0,0,0,.22)}.modal-card h2{margin:0 0 8px;color:#15366f}.modal-card p{color:#61708a;line-height:1.6}.cache-toggle{position:fixed;right:22px;bottom:22px;z-index:12;background:#2f72ff;color:white;box-shadow:0 12px 28px rgba(47,114,255,.26)}.cache-drawer{position:fixed;right:22px;bottom:76px;width:min(390px,calc(100vw - 44px));max-height:min(660px,76vh);z-index:12;background:white;border:1px solid #dbe8ff;border-radius:22px;box-shadow:0 22px 60px rgba(30,64,110,.20);padding:16px;display:flex;flex-direction:column;gap:12px}.cache-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}.cache-head h2{margin:0;color:#15366f;font-size:19px}.cache-head p{margin:6px 0 0;color:#7a879b;font-size:12px}.cache-search{flex:0 0 auto}.cache-actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.cache-list{overflow:auto;display:flex;flex-direction:column;gap:10px;padding-right:2px}.cache-empty{padding:28px;text-align:center;color:#8291aa;background:#f9fbff;border:1px dashed #d7e5ff;border-radius:16px}.cache-item{border:1px solid #e1ebff;background:#f9fbff;border-radius:16px;padding:12px}.cache-item-title{font-weight:700;color:#18386c;margin-bottom:4px}.cache-item-meta{font-size:12px;color:#7c8ca7}.cache-item p{margin:8px 0 10px;color:#50627d;font-size:13px;line-height:1.5;max-height:42px;overflow:hidden}.cache-item-actions{display:flex;gap:8px}.vec,.hat,.bar{display:inline-block;position:relative;padding:0 .04em}.vec::after{content:"→";position:absolute;left:0;right:0;top:-.88em;text-align:center;font-size:.72em;line-height:1}.hat::after{content:"^";position:absolute;left:0;right:0;top:-.78em;text-align:center;font-size:.78em;line-height:1}.bar::after{content:"";position:absolute;left:.02em;right:.02em;top:-.18em;border-top:1.4px solid currentColor}.latex-preview{font-size:18px}.latex-preview-item{min-height:58px;display:flex;align-items:center;justify-content:center}.latex-block{width:100%;overflow-x:auto;white-space:nowrap}.latex-line{font-family:'Times New Roman','Cambria Math','Microsoft YaHei',serif;font-size:17px}.matrix-wrap{margin:0 4px}.matrix-bracket{font-family:'Times New Roman','Cambria Math',serif;font-weight:400}.frac{font-family:'Times New Roman','Cambria Math',serif}.frac-top,.frac-bottom{min-width:18px;text-align:center}@media(max-width:1150px){.layout{grid-template-columns:1fr;--panel-h:auto}.panel-card{height:auto;max-height:none;min-height:0}.tools-card{position:static}.topbar{align-items:flex-start;flex-direction:column}textarea{height:360px}.half-card{height:430px}.third-card{height:330px}.cache-drawer{right:12px;bottom:70px}.cache-toggle{right:12px;bottom:16px}.answer-preview{min-height:220px}}

/* layout hard-fix: prevent front-end overflow/overlap */
.app-shell{
  height:100vh;
  overflow:hidden;
}
.layout{
  height:calc(100vh - 128px);
  max-height:calc(100vh - 128px);
  align-items:stretch;
}
.panel-card{
  height:100%;
  min-height:0;
  max-height:none;
}
.input-card,
.tools-card{
  overflow:hidden;
}
.input-card textarea{
  min-height:0;
}
.tools-card{
  position:static;
  overflow-y:auto;
  padding-right:14px;
}
.center-stack{
  height:100%;
  min-height:0;
  overflow-y:auto;
  overflow-x:hidden;
  padding-right:4px;
}
.third-card{
  display:flex;
  flex-direction:column;
  flex:0 0 auto;
  height:auto;
  min-height:230px;
  overflow:hidden;
}
.answer-card{
  min-height:260px;
}
.diagram-card{
  min-height:310px;
}
.handwriting-card{
  min-height:360px;
}
.answer-preview,
.image-preview,
.diagram-panel-fixed{
  flex:1 1 auto;
  min-height:0;
  overflow:auto;
}
.diagram-panel-fixed{
  max-height:260px;
}
.diagram-canvas{
  min-height:210px;
  max-height:235px;
  overflow:auto;
  display:flex;
  align-items:center;
  justify-content:center;
}
.diagram-canvas svg{
  max-width:100%;
  max-height:210px;
  width:auto;
  height:auto;
}
.image-preview img{
  max-height:620px;
  object-fit:contain;
}
.cache-toggle{
  z-index:30;
}
@media(max-width:1150px){
  .app-shell{
    height:auto;
    min-height:100vh;
    overflow:auto;
  }
  .layout{
    height:auto;
    max-height:none;
  }
  .center-stack{
    height:auto;
    overflow:visible;
  }
  .third-card,
  .panel-card{
    height:auto;
    min-height:0;
  }
  .diagram-panel-fixed,
  .diagram-canvas{
    max-height:none;
  }
  .diagram-canvas svg{
    max-height:none;
  }
}


.check-row{
  display:flex;
  align-items:center;
  gap:8px;
  font-size:13px;
  color:#334155;
  margin:2px 0 6px;
}
.check-row input{
  width:16px;
  height:16px;
  margin:0;
}


.answer-edit-toolbar{
  display:flex;
  gap:8px;
  padding:0 16px 8px;
  flex-wrap:wrap;
}
.answer-edit-toolbar button{
  padding:8px 11px;
  font-size:12px;
}
.answer-edit-box{
  flex:1 1 auto;
  min-height:220px;
  margin:0 16px 16px;
  width:calc(100% - 32px);
  border:1px solid rgba(59,130,246,.22);
  border-radius:14px;
  background:#fbfdff;
  padding:14px;
  resize:vertical;
  font-size:15px;
  line-height:1.8;
  color:#1f2937;
  font-family:"Microsoft YaHei", "PingFang SC", sans-serif;
  outline:none;
}
.answer-edit-box:focus{
  border-color:#60a5fa;
  box-shadow:0 0 0 3px rgba(96,165,250,.16);
}


.font-upload-row{
  display:flex;
  align-items:center;
  gap:8px;
  font-size:13px;
  color:#334155;
}
.font-upload-row input{
  max-width:170px;
  font-size:12px;
}


.setting-hint{
  display:inline-block;
  margin-left:6px;
  font-size:12px;
  color:#64748b;
}


/* Sakura cute frontend skin */
:root{
  --sakura-bg-1:#fff7fd;
  --sakura-bg-2:#f4efff;
  --sakura-bg-3:#eff7ff;
  --sakura-pink:#f58bc4;
  --sakura-purple:#8c63d9;
  --sakura-ink:#35264d;
  --sakura-line:#efd8ff;
}
body{
  background:
    radial-gradient(circle at 14% 9%, rgba(255,190,223,.52), transparent 28%),
    radial-gradient(circle at 86% 4%, rgba(199,176,255,.50), transparent 30%),
    linear-gradient(135deg,var(--sakura-bg-1),var(--sakura-bg-2) 48%,var(--sakura-bg-3));
  color:var(--sakura-ink);
}
.app-shell{
  position:relative;
  overflow:hidden;
}
.app-shell::before{
  content:"";
  position:fixed;
  inset:0;
  pointer-events:none;
  background:
    radial-gradient(circle at 8% 24%, rgba(255,139,194,.18) 0 7px, transparent 8px),
    radial-gradient(circle at 26% 16%, rgba(255,209,232,.24) 0 5px, transparent 6px),
    radial-gradient(circle at 74% 14%, rgba(255,139,194,.18) 0 6px, transparent 7px),
    radial-gradient(circle at 92% 30%, rgba(255,209,232,.25) 0 5px, transparent 6px),
    radial-gradient(circle at 14% 84%, rgba(255,139,194,.20) 0 8px, transparent 9px),
    radial-gradient(circle at 80% 86%, rgba(194,168,255,.20) 0 7px, transparent 8px);
  opacity:.9;
}
.hero-topbar{
  position:relative;
  min-height:172px;
  padding:28px 30px;
  border:1px solid rgba(255,255,255,.72);
  border-radius:30px;
  background:
    linear-gradient(120deg,rgba(255,255,255,.82),rgba(255,240,250,.72)),
    radial-gradient(circle at 72% 14%,rgba(255,160,210,.40),transparent 34%),
    radial-gradient(circle at 18% 80%,rgba(174,147,255,.28),transparent 30%);
  box-shadow:0 24px 60px rgba(134,87,180,.18);
  backdrop-filter:blur(18px);
  overflow:hidden;
}
.hero-topbar::before{
  content:"";
  position:absolute;
  inset:-80px -60px auto auto;
  width:390px;
  height:260px;
  background:radial-gradient(circle,rgba(255,145,202,.34),transparent 67%);
  transform:rotate(-12deg);
}
.hero-topbar::after{
  content:"✦ ｡･ﾟ🌸･｡ ✦";
  position:absolute;
  right:34px;
  bottom:18px;
  color:rgba(139,92,246,.38);
  font-size:18px;
  letter-spacing:8px;
}
.hero-brand{
  position:relative;
  z-index:1;
  display:flex;
  align-items:center;
  gap:22px;
}
.hero-badge{
  width:96px;
  height:96px;
  border-radius:30px;
  padding:7px;
  background:linear-gradient(135deg,#fff,#ffe8f6 42%,#eaddff);
  box-shadow:0 14px 30px rgba(151,101,210,.20), inset 0 0 0 1px rgba(255,255,255,.86);
}
.hero-badge img{
  width:100%;
  height:100%;
  border-radius:24px;
  object-fit:cover;
  display:block;
}
.hero-copy{
  min-width:0;
}
.hero-kicker{
  display:inline-flex;
  align-items:center;
  gap:8px;
  padding:7px 12px;
  border-radius:999px;
  background:rgba(255,255,255,.72);
  color:#8b5cf6;
  font-size:13px;
  font-weight:700;
  box-shadow:inset 0 0 0 1px rgba(226,208,255,.72);
}
.hero-kicker::before{
  content:"✧";
  color:#f472b6;
}
.hero-copy h1{
  margin:10px 0 2px;
  font-size:52px;
  line-height:1.02;
  letter-spacing:-1.5px;
  color:#4a2c6b;
  text-shadow:0 6px 18px rgba(158,97,185,.18);
}
.hero-copy h1::after{
  content:" · Handwriting Engine";
  font-size:26px;
  color:#5b4b7b;
  letter-spacing:0;
  margin-left:10px;
  font-weight:600;
}
.hero-copy p{
  margin:8px 0 0;
  color:#715f8f;
  font-weight:600;
}
.hero-actions{
  position:relative;
  z-index:1;
  display:flex;
  align-items:center;
  gap:12px;
  flex-wrap:wrap;
  justify-content:flex-end;
}
.hero-chip{
  padding:9px 13px;
  border-radius:999px;
  background:rgba(255,255,255,.72);
  border:1px solid rgba(236,204,255,.80);
  color:#8b5cf6;
  font-size:13px;
  font-weight:700;
}
.card{
  border:1px solid rgba(239,216,255,.92);
  background:rgba(255,255,255,.78);
  box-shadow:0 18px 44px rgba(125,85,180,.12);
  backdrop-filter:blur(14px);
}
.card h2{
  color:#5b3d86;
}
.card-head span{
  color:#9b82b8;
}
button{
  background:linear-gradient(135deg,#fff,#f8ecff);
  color:#6d3fb2;
  border:1px solid rgba(219,198,255,.95);
  box-shadow:0 8px 18px rgba(139,92,246,.08);
}
.primary{
  background:linear-gradient(135deg,#a78bfa,#f472b6);
  color:#fff;
  border:0;
  box-shadow:0 14px 28px rgba(244,114,182,.28);
}
.light{
  background:rgba(255,255,255,.78);
  border:1px solid rgba(225,210,255,.95);
  color:#6d3fb2;
}
textarea,.answer-preview,.diagram-panel-fixed,.diagram-canvas{
  background:rgba(255,255,255,.72);
  border-color:rgba(230,213,255,.92);
}
.upload-box{
  background:linear-gradient(135deg,rgba(255,255,255,.70),rgba(255,240,250,.72));
  border-color:rgba(232,190,255,.86);
}
.tools-card label{
  color:#5c4a78;
  font-weight:700;
}
input[type="range"]{
  accent-color:#f472b6;
}
.cache-toggle{
  background:linear-gradient(135deg,#ffffff,#ffeaf7);
  border:1px solid rgba(244,194,224,.9);
  color:#8b4a90;
}
.modal-card{
  border:1px solid rgba(255,255,255,.76);
  background:rgba(255,255,255,.88);
  box-shadow:0 24px 80px rgba(129,78,164,.22);
}
@media (max-width: 900px){
  .hero-topbar{
    align-items:flex-start;
    flex-direction:column;
    padding:22px;
  }
  .hero-brand{
    align-items:flex-start;
  }
  .hero-badge{
    width:72px;
    height:72px;
    border-radius:22px;
  }
  .hero-badge img{
    border-radius:17px;
  }
  .hero-copy h1{
    font-size:36px;
  }
  .hero-copy h1::after{
    display:block;
    margin:6px 0 0;
    font-size:20px;
  }
}


/* cute scroll + softer sakura polish */
html, body{
  min-height:100%;
  overflow-x:hidden;
  overflow-y:auto;
}
.app-shell{
  min-height:100vh;
  height:auto;
  overflow-x:hidden;
  overflow-y:visible;
  padding-bottom:42px;
}
.layout{
  --panel-h:auto;
  min-height:0;
  align-items:start;
}
.panel-card{
  height:auto;
  min-height:560px;
  max-height:none;
}
.input-card,
.tools-card{
  max-height:none;
}
.center-stack{
  height:auto;
  max-height:none;
  overflow:visible;
}
.half-card{
  height:auto;
  min-height:310px;
}
.third-card{
  height:auto;
  min-height:260px;
}
textarea{
  min-height:520px;
  max-height:68vh;
}
.input-card textarea{
  min-height:520px;
  max-height:68vh;
}
.tools-card{
  position:sticky;
  top:18px;
  max-height:calc(100vh - 36px);
  overflow-y:auto;
  scrollbar-width:thin;
}
.hero-topbar{
  margin-top:6px;
  margin-bottom:18px;
}
.hero-copy h1{
  position:relative;
}
.hero-copy h1::before{
  content:"🌸";
  font-size:24px;
  position:absolute;
  left:-34px;
  top:7px;
  filter:drop-shadow(0 5px 10px rgba(244,114,182,.25));
}
.hero-copy h1::after{
  content:" · Handwriting Engine";
  font-size:26px;
  color:#5b4b7b;
  letter-spacing:0;
  margin-left:10px;
  font-weight:600;
}
.hero-actions::before{
  content:"✦  ✦";
  padding:9px 13px;
  border-radius:999px;
  background:rgba(255,255,255,.72);
  border:1px solid rgba(236,204,255,.80);
  color:#a855f7;
  font-size:13px;
  font-weight:800;
}
.card{
  position:relative;
}
.card::before{
  content:"";
  position:absolute;
  inset:0;
  pointer-events:none;
  border-radius:inherit;
  background:
    radial-gradient(circle at 92% 10%, rgba(255,189,220,.30), transparent 18%),
    radial-gradient(circle at 8% 92%, rgba(196,181,253,.20), transparent 20%);
  opacity:.65;
}
.card > *{
  position:relative;
  z-index:1;
}
.card h2::before{
  content:"✧ ";
  color:#f472b6;
}
.primary{
  position:relative;
  overflow:hidden;
}
.primary::after{
  content:"";
  position:absolute;
  inset:-40% auto auto -20%;
  width:70%;
  height:180%;
  transform:rotate(18deg);
  background:linear-gradient(90deg,transparent,rgba(255,255,255,.35),transparent);
  opacity:.55;
}
button{
  transition:transform .16s ease, box-shadow .16s ease, filter .16s ease;
}
button:hover{
  transform:translateY(-1px);
  box-shadow:0 12px 26px rgba(139,92,246,.15);
}
.upload-box::after{
  content:"拖进来就可以喵";
  margin-left:auto;
  color:#c084fc;
  font-size:12px;
  font-weight:700;
}
.answer-preview,
.diagram-canvas,
.diagram-panel-fixed,
textarea{
  box-shadow:inset 0 0 0 1px rgba(255,255,255,.65);
}
.cache-toggle{
  z-index:20;
}
@media (max-width: 1180px){
  .layout{
    grid-template-columns:1fr;
  }
  .tools-card{
    position:static;
    max-height:none;
  }
  textarea,
  .input-card textarea{
    max-height:none;
  }
}


/* layout clean fix: inner long-scroll panels, no broken right toolbar */
html, body{
  height:100%;
  overflow:hidden;
}
body{
  overscroll-behavior:none;
}
.app-shell{
  height:100vh;
  min-height:0;
  overflow:hidden;
  padding:18px 22px 18px;
}
.hero-topbar{
  min-height:128px;
  max-width:1380px;
  margin:0 auto 14px;
  padding:22px 26px;
  border-radius:28px;
}
.hero-topbar::after{
  content:"";
}
.hero-actions::before{
  content:none !important;
  display:none !important;
}
.hero-badge{
  width:76px;
  height:76px;
  border-radius:24px;
}
.hero-badge img{
  border-radius:18px;
}
.hero-copy h1{
  font-size:44px;
}
.hero-copy h1::before{
  content:"";
}
.hero-copy h1::after{
  font-size:23px;
}
.hero-copy p{
  font-size:15px;
}
.layout{
  --panel-h:calc(100vh - 188px);
  height:var(--panel-h);
  min-height:0;
  max-width:1380px;
  margin:0 auto;
  display:grid;
  grid-template-columns:minmax(320px,.95fr) minmax(430px,1.1fr) minmax(240px,280px);
  gap:16px;
  align-items:stretch;
  overflow:visible;
}
.panel-card,
.input-card,
.tools-card{
  height:var(--panel-h);
  min-height:0;
  max-height:var(--panel-h);
  overflow:hidden;
}
.input-card,
.tools-card{
  display:flex;
  flex-direction:column;
}
.input-card textarea{
  min-height:0;
  max-height:none;
  flex:1 1 auto;
  overflow:auto;
}
.center-stack{
  height:var(--panel-h);
  min-height:0;
  max-height:var(--panel-h);
  display:flex;
  flex-direction:column;
  gap:16px;
  overflow:hidden;
}
.half-card{
  height:auto;
  min-height:0;
  flex:1 1 0;
  overflow:hidden;
}
.third-card{
  height:auto;
  min-height:0;
  flex:1 1 0;
  overflow:hidden;
}
.answer-card,
.diagram-card{
  display:flex;
  flex-direction:column;
}
.answer-preview,
.diagram-panel-fixed,
.diagram-canvas{
  min-height:0;
  flex:1 1 auto;
  overflow:auto;
}
.tools-card{
  position:static;
  top:auto;
  overflow-y:auto;
  scrollbar-width:thin;
  padding:16px;
}
.tools-card button{
  width:100%;
  min-height:42px;
  margin:0;
  display:flex;
  align-items:center;
  justify-content:center;
  white-space:nowrap;
}
.tools-card .divider{
  margin:12px 0;
  flex:0 0 auto;
}
.tools-card label{
  display:flex;
  flex-direction:column;
  gap:6px;
  margin:8px 0;
}
.tools-card select,
.tools-card input[type="number"],
.tools-card input[type="range"]{
  width:100%;
}
.tools-card .font-upload-row{
  display:flex;
  flex-direction:column;
  align-items:stretch;
}
.tools-card .font-upload-row input{
  max-width:100%;
}
.upload-box::after{
  content:"";
  display:none;
}
.card{
  padding:16px;
}
.card-head{
  margin-bottom:10px;
}
.cache-toggle{
  right:20px;
  bottom:18px;
}
.cache-drawer{
  max-height:calc(100vh - 80px);
  overflow:auto;
}
@media (max-width: 1180px){
  html, body{
    height:auto;
    overflow:auto;
  }
  .app-shell{
    height:auto;
    overflow:visible;
  }
  .layout{
    height:auto;
    max-height:none;
    grid-template-columns:1fr;
  }
  .panel-card,
  .input-card,
  .tools-card,
  .center-stack{
    height:auto;
    max-height:none;
  }
  .input-card textarea{
    min-height:420px;
  }
}

</style>
