(function () {
  "use strict";

  const ABI = "proofscript-json-v1";
  const SCHEMA_VERSION = "0.0.0";
  const DEFAULTS = { inputBytes: 64 * 1024, outputBytes: 8 * 1024 * 1024, timeoutMs: 2000 };
  const bundles = new Map();
  const renderers = new Map();

  function resourceUrl(base, ref) {
    if (!ref || !ref.$resource || typeof ref.$resource.path !== "string") throw new Error("invalid resource reference");
    const path = ref.$resource.path;
    if (path.startsWith("/") || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(path)) throw new Error("resource path must be relative");
    const url = new URL(path, base);
    const root = new URL(".", base);
    if (url.origin !== root.origin || !url.pathname.startsWith(root.pathname)) throw new Error("resource path escapes project root");
    return url;
  }
  async function sha256Hex(bytes) {
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
  }
  async function fetchVerified(base, ref) {
    const descriptor = ref.$resource;
    let response;
    try {
      response = await fetch(resourceUrl(base, ref), { credentials: "same-origin", cache: "force-cache" });
    } catch (error) {
      if (location.protocol === "file:") throw new Error("Computation requires HTTP. Run `ps4html serve` and open the served URL.");
      throw new Error(`resource fetch failed: ${error.message || error}`);
    }
    if (!response.ok) throw new Error(`resource load failed: ${response.status}`);
    const bytes = await response.arrayBuffer();
    if (descriptor.byteSize !== undefined && bytes.byteLength !== descriptor.byteSize) throw new Error("resource byte size mismatch");
    if (await sha256Hex(bytes) !== descriptor.hash) throw new Error("resource SHA-256 mismatch");
    return bytes;
  }
  function workerSource() {
    return `self.onmessage = async e => { const m=e.data; try { if (!self.instance) { const f=(await import(m.moduleUrl)).default; self.instance=await f({locateFile:p=>p.endsWith('.wasm')?m.wasmUrl:new URL(p,m.moduleUrl).href}); self.instance._proof_script_init(); } const i=self.instance, enc=new TextEncoder(), dec=new TextDecoder('utf-8',{fatal:true}), eb=enc.encode(m.entry), ib=enc.encode(JSON.stringify(m.input)); if (ib.length>${DEFAULTS.inputBytes}) throw Error('input JSON exceeds limit'); const ep=i._proof_script_alloc(eb.length), ip=i._proof_script_alloc(ib.length); i.HEAPU8.set(eb,ep); i.HEAPU8.set(ib,ip); let cap=64*1024, op=i._proof_script_alloc(cap); try { let n=i._proof_script_invoke(ep,eb.length,ip,ib.length,op,cap); if(n>cap) { if(n>${DEFAULTS.outputBytes}) throw Error('output JSON exceeds limit'); i._proof_script_free(op); cap=n; op=i._proof_script_alloc(cap); n=i._proof_script_invoke(ep,eb.length,ip,ib.length,op,cap); } self.postMessage({requestId:m.requestId,result:JSON.parse(dec.decode(i.HEAPU8.slice(op,op+n)))}); } finally { i._proof_script_free(ep); i._proof_script_free(ip); i._proof_script_free(op); } } catch (x) { self.postMessage({requestId:m.requestId,transportError:String(x.message||x)}); } };`;
  }
  async function createClient(execution, base, cacheKey) {
    const [manifestBytes] = await Promise.all([fetchVerified(base, execution.manifest), fetchVerified(base, execution.module), fetchVerified(base, execution.wasm)]);
    const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
    if (manifest.schemaVersion !== SCHEMA_VERSION || manifest.abi !== ABI) throw new Error("Unsupported computation bundle schema or ABI");
    const source = URL.createObjectURL(new Blob([workerSource()], { type: "text/javascript" }));
    const worker = new Worker(source, { type: "module" });
    URL.revokeObjectURL(source);
    let serial = Promise.resolve();
    return { invoke(entry, input, signal) { const requestId=crypto.randomUUID(); const task=serial.then(() => new Promise((resolve,reject) => { const discard=()=>{ worker.terminate(); bundles.delete(cacheKey); }; const timer=setTimeout(() => { discard(); reject(new Error("computation timed out")); }, DEFAULTS.timeoutMs); const cleanup=()=>clearTimeout(timer); const onAbort=()=>{ discard(); cleanup(); reject(new DOMException("Aborted","AbortError")); }; const onMessage=e=>{ if(e.data.requestId!==requestId)return; cleanup(); signal?.removeEventListener("abort",onAbort); worker.removeEventListener("message",onMessage); e.data.transportError?reject(new Error(e.data.transportError)):resolve(e.data.result); }; if(signal?.aborted) return onAbort(); signal?.addEventListener("abort",onAbort,{once:true}); worker.addEventListener("message",onMessage); worker.postMessage({requestId,entry,input,moduleUrl:resourceUrl(base,execution.module).href,wasmUrl:resourceUrl(base,execution.wasm).href}); })); serial=task.catch(()=>{}); return task; } };
  }
  function register(renderer, loader) { renderers.set(renderer, loader); }
  async function mount(root, base=new URL(document.documentElement.dataset.projectBaseUrl || "./", document.baseURI)) {
    if (location.protocol === "file:") throw new Error("Computation requires HTTP. Run `ps4html serve` and open the served URL.");
    const value=JSON.parse(root.querySelector("[data-computation-value]").textContent), execution=value.execution;
    if (value.schemaVersion !== SCHEMA_VERSION) throw new Error(`Unsupported computation schema: ${value.schemaVersion}`);
    if (execution.status !== "ready" || execution.backend !== "wasm" || execution.abi !== ABI) {
      const fallback = root.querySelector("[data-computation-fallback]");
      const status = root.querySelector("[data-computation-status]");
      const target = root.querySelector("[data-computation-renderer]");
      if (target) target.hidden = true;
      if (fallback) fallback.hidden = false;
      if (status && execution.status === "pending") status.textContent = "Computation resources pending";
      return;
    }
    const loader=renderers.get(value.renderer); if (!loader) throw new Error(`Unknown computation renderer: ${value.renderer}`);
    const fallback=root.querySelector("[data-computation-fallback]"); const target=root.querySelector("[data-computation-renderer]");
    target.hidden=false;
    target.innerHTML="<p class=\"computation-loading\">Loading computation renderer...</p>";
    const clientKey=execution.module.$resource.hash; let clientPromise=bundles.get(clientKey); if (!clientPromise) { clientPromise=createClient(execution,new URL(base),clientKey); bundles.set(clientKey,clientPromise); clientPromise.catch(()=>bundles.delete(clientKey)); } const client=await clientPromise;
    try {
      await loader({ component:value, compute:(input,signal)=>client.invoke(execution.entry,input,signal), element:target });
      fallback.hidden=true;
      root.querySelector("[data-computation-status]").textContent="Ready";
    } catch (error) {
      target.hidden=true;
      throw error;
    }
  }
  window.PS4HTMLComputation = { register, mount, resourceUrl, fetchVerified };
  document.addEventListener("DOMContentLoaded", () => document.querySelectorAll("[data-computation]").forEach(root => {
    root.querySelector("[data-computation-status]").textContent = "Loading computation renderer...";
    mount(root).catch(error => {
      root.dataset.error="true";
      const message = error && error.message ? error.message : String(error);
      root.querySelector("[data-computation-status]").textContent=message;
      root.querySelector("[data-computation-fallback]").textContent=`Computation failed: ${message}`;
      root.querySelector("[data-computation-fallback]").hidden=false;
    });
  }));
})();
