import html
import json
from string import Template


TEMPLATE = Template('''<section class="computation-component" data-computation data-renderer="$renderer" data-status="$status" data-bundle-id="$bundle_id">
  <header class="computation-header"><h2>$title</h2><p class="computation-status" data-computation-status>$status_text</p></header>
  <div class="computation-fallback" data-computation-fallback>$fallback</div>
  <div class="computation-renderer" data-computation-renderer hidden></div>
  <script type="application/json" data-computation-value>$value</script>
</section>''')


def render_computation(value):
    if not isinstance(value, dict):
        return '<section class="computation-component computation-error"><strong>Invalid computation component</strong></section>'
    metadata = value.get("metadata") if isinstance(value.get("metadata"), dict) else {}
    execution = value.get("execution") if isinstance(value.get("execution"), dict) else {}
    status = execution.get("status")
    title = metadata.get("title") or value.get("renderer") or "Computation"
    status_text = "计算资源尚未完成构建" if status == "pending" else "计算资源已就绪" if status == "ready" else "计算组件错误"
    payload = value.get("payload")
    fallback = payload.get("fallback") if isinstance(payload, dict) else None
    if isinstance(fallback, dict):
        fallback = fallback.get("summary")
    if not isinstance(fallback, str):
        fallback = metadata.get("title") or "Embedded computation"
    serialized = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    serialized = serialized.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    return TEMPLATE.substitute(
        renderer=html.escape(str(value.get("renderer", "")), quote=True),
        status=html.escape(str(status or "invalid"), quote=True),
        bundle_id=html.escape(str(execution.get("bundleId", "")), quote=True),
        title=html.escape(str(title)),
        status_text=html.escape(status_text),
        fallback=html.escape(str(fallback)),
        value=serialized,
    )
