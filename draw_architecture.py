import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np

# Setup
fig, ax = plt.subplots(1, 1, figsize=(16, 12))
ax.set_xlim(0, 16)
ax.set_ylim(0, 12)
ax.axis('off')
ax.set_facecolor('#f8f9fa')
fig.patch.set_facecolor('#f8f9fa')

# Colors
colors = {
    'user': '#e3f2fd',
    'ingress': '#fff3e0',
    'service': '#e8f5e9',
    'pod': '#fce4ec',
    'store': '#f3e5f5',
    'probe': '#e0f7fa',
    'metrics': '#fff8e1',
    'k8s': '#ffebee',
    'arrow': '#546e7a',
    'text': '#263238',
    'label': '#455a64',
}

def draw_box(ax, x, y, w, h, label, sublabel=None, color='white', text_color='#263238', fontsize=11, subfontsize=9):
    """Draw a rounded rectangle with text."""
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05,rounding_size=0.2",
                         facecolor=color, edgecolor='#37474f', linewidth=2)
    ax.add_patch(box)
    ax.text(x + w/2, y + h/2 + 0.15, label, ha='center', va='center',
            fontsize=fontsize, fontweight='bold', color=text_color)
    if sublabel:
        ax.text(x + w/2, y + h/2 - 0.25, sublabel, ha='center', va='center',
                fontsize=subfontsize, color='#546e7a', style='italic')
    return box

def draw_arrow(ax, x1, y1, x2, y2, label=None, color='#546e7a', style='->', lw=2):
    """Draw an arrow between two points."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle=style, color=color, lw=lw,
                                connectionstyle='arc3,rad=0'))
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx, my + 0.25, label, ha='center', va='bottom',
                fontsize=8, color=color, fontweight='bold',
                bbox=dict(boxstyle='round,pad=0.2', facecolor='white', edgecolor='none', alpha=0.9))

def draw_dashed_arrow(ax, x1, y1, x2, y2, label=None, color='#78909c'):
    """Draw a dashed arrow (for probes/checks)."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=1.5, ls='--',
                                connectionstyle='arc3,rad=0'))
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx, my + 0.2, label, ha='center', va='bottom',
                fontsize=8, color=color, style='italic')

# ========== TITLE ==========
ax.text(8, 11.5, 'TaskGuard Architecture', ha='center', va='center',
        fontsize=22, fontweight='bold', color=colors['text'])
ax.text(8, 11.1, 'How all the pieces connect together', ha='center', va='center',
        fontsize=12, color=colors['label'])

# ========== LAYER LABELS ==========
ax.text(0.5, 10.2, 'EXTERNAL', ha='left', va='center',
        fontsize=10, fontweight='bold', color='#1565c0')
ax.text(0.5, 7.7, 'KUBERNETES CLUSTER', ha='left', va='center',
        fontsize=10, fontweight='bold', color='#2e7d32')
ax.text(0.5, 2.2, 'OBSERVABILITY', ha='left', va='center',
        fontsize=10, fontweight='bold', color='#ef6c00')

# ========== EXTERNAL LAYER ==========
draw_box(ax, 6.5, 9.3, 3, 0.9, 'You / Browser', 
         color=colors['user'], fontsize=12)

# ========== K8s CLUSTER (dashed boundary) ==========
cluster = FancyBboxPatch((1.5, 3.3), 13, 5.8, boxstyle="round,pad=0.05,rounding_size=0.3",
                         facecolor='white', edgecolor='#90a4ae', linewidth=2, linestyle='--', alpha=0.5)
ax.add_patch(cluster)

# Ingress
draw_box(ax, 6.5, 7.8, 3, 0.9, 'Ingress', 'nginx', 
         color=colors['ingress'], fontsize=11)

# Service
draw_box(ax, 6.5, 6.0, 3, 0.9, 'Service', 'ClusterIP', 
         color=colors['service'], fontsize=11)

# Pod (bigger, contains the app)
pod_box = FancyBboxPatch((4.5, 3.5), 7, 2.0, boxstyle="round,pad=0.05,rounding_size=0.2",
                         facecolor=colors['pod'], edgecolor='#37474f', linewidth=2)
ax.add_patch(pod_box)
ax.text(8, 5.1, 'Pod', ha='center', va='center',
        fontsize=11, fontweight='bold', color=colors['text'])

# TaskGuard app inside pod
draw_box(ax, 5.0, 3.7, 3.5, 1.1, 'TaskGuard App', 'Go HTTP Server',
         color='#f8bbd0', fontsize=10)

# In-memory Store inside pod
draw_box(ax, 9.0, 3.7, 2.2, 1.1, 'Store', 'in-memory',
         color=colors['store'], fontsize=10)

# ========== PROBES (branching off) ==========
# Liveness probe
draw_box(ax, 1.0, 4.8, 2.5, 0.7, '/healthz', 'Liveness Probe',
         color=colors['probe'], fontsize=9)

# Readiness probe  
draw_box(ax, 1.0, 3.6, 2.5, 0.7, '/readyz', 'Readiness Probe',
         color=colors['probe'], fontsize=9)

# ========== KUBELET ==========
draw_box(ax, 0.8, 6.2, 2.8, 0.8, 'kubelet', 'Node Agent',
         color=colors['k8s'], fontsize=10)

# ========== OBSERVABILITY LAYER ==========
# Prometheus
draw_box(ax, 6.5, 1.2, 3, 0.9, 'Prometheus', 'Metrics Server',
         color=colors['metrics'], fontsize=11)

# ========== ARROWS ==========
# User -> Ingress
draw_arrow(ax, 8, 9.3, 8, 8.7, 'HTTP request')

# Ingress -> Service
draw_arrow(ax, 8, 7.8, 8, 6.9)

# Service -> Pod
draw_arrow(ax, 8, 6.0, 8, 5.5, 'routes traffic')

# TaskGuard -> Store (internal)
draw_arrow(ax, 8.5, 4.25, 9.0, 4.25, '', lw=1.5)

# kubelet -> healthz
draw_dashed_arrow(ax, 3.6, 6.6, 2.5, 5.5, 'checks every 10s')

# kubelet -> readyz
draw_dashed_arrow(ax, 3.6, 6.2, 2.5, 4.3, 'checks every 10s')

# kubelet -> Pod (for actions)
draw_dashed_arrow(ax, 3.6, 6.4, 5.0, 5.0, 'can restart', color='#d32f2f')

# Prometheus -> Metrics
draw_dashed_arrow(ax, 8, 2.1, 8, 3.7, 'scrapes /metrics', color='#ef6c00')

# ========== ANNOTATIONS / LEGEND ==========
legend_y = 0.6
ax.text(1.5, legend_y, 'Solid = Traffic flow', ha='left', va='center',
        fontsize=9, color=colors['text'])
ax.text(5.5, legend_y, 'Dashed = Checks / Scrapes', ha='left', va='center',
        fontsize=9, color='#78909c')
ax.text(10.0, legend_y, 'Data disappears when pod restarts!', ha='left', va='center',
        fontsize=9, color='#d32f2f', fontweight='bold')

# ========== SIDE ANNOTATIONS ==========
# Health probe annotation
ax.text(0.3, 4.2, '"Are you\nalive?"', ha='center', va='center',
        fontsize=8, color='#00838f', style='italic')
ax.text(0.3, 3.0, '"Ready to\nserve?"', ha='center', va='center',
        fontsize=8, color='#00838f', style='italic')

# Store annotation
ax.text(12.5, 4.2, 'Tasks live here\n(like a whiteboard!\nErased on restart)', 
        ha='center', va='center', fontsize=8, color='#6a1b9a',
        bbox=dict(boxstyle='round,pad=0.3', facecolor='#f3e5f5', edgecolor='#6a1b9a', alpha=0.7))

# Graceful shutdown note
ax.text(12.5, 5.8, 'SIGTERM -> finish\nrequests -> exit', 
        ha='center', va='center', fontsize=8, color='#c62828',
        bbox=dict(boxstyle='round,pad=0.3', facecolor='#ffebee', edgecolor='#c62828', alpha=0.7))

plt.tight_layout()
plt.savefig('/Users/nasif.bhugaloo/Documents/1/Kube/taskguard/taskguard_architecture.png', dpi=150, bbox_inches='tight', 
            facecolor='#f8f9fa', edgecolor='none')
plt.close()
print("Diagram saved to taskguard_architecture.png")
