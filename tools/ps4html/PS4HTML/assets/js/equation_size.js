function alignAndScaleMath() {
    // 1. 获取所有的推导行
    const blocks = document.querySelectorAll('.step-block');
    
    // 2. 将它们按父元素分组（确保不同的推导模块之间互不影响）
    const groups = new Map();
    blocks.forEach(block => {
        const parent = block.parentElement;
        if (!groups.has(parent)) {
            groups.set(parent, []);
        }
        groups.get(parent).push(block);
    });

    // 3. 核心计算：寻找最宽项并设置 Flex Basis
    groups.forEach(groupBlocks => {
        let maxLhsWidth = 0;
        let maxRhsWidth = 0;

        // 【第一轮遍历】：重置样式，并测量每一侧所需的“物理最大宽度”
        groupBlocks.forEach(block => {
            const lhs = block.querySelector('.step-lhs');
            const rhs = block.querySelector('.step-rhs');

            if (lhs) {
                lhs.style.flex = '0 0 auto';      // 临时收缩到最小
                lhs.style.transform = 'scale(1)'; // 取消缩放干扰
                maxLhsWidth = Math.max(maxLhsWidth, lhs.scrollWidth);
            }
            if (rhs) {
                rhs.style.flex = '0 0 auto';
                rhs.style.transform = 'scale(1)';
                maxRhsWidth = Math.max(maxRhsWidth, rhs.scrollWidth);
            }
        });

        // 【第二轮遍历】：利用 Flexbox 原生机制实现“空白平分”
        // flex: 1 1 {基础宽度}px 
        // 这表示：保底分配最大内容宽度，然后将剩余的屏幕空白 1:1 绝对平分给两侧
        groupBlocks.forEach(block => {
            const lhs = block.querySelector('.step-lhs');
            const rhs = block.querySelector('.step-rhs');

            if (lhs) lhs.style.flex = `1 1 ${maxLhsWidth}px`;
            if (rhs) rhs.style.flex = `1 1 ${maxRhsWidth}px`;
        });
    });

    // 4. 【第三轮遍历】：超长缩放保护（防止手机窄屏超出）
    // 此时浏览器已经完成了排版，如果屏幕不够大导致实际空间小于内容空间，按比例缩放文字
    const mathContainers = document.querySelectorAll('.step-lhs, .step-rhs');
    mathContainers.forEach(container => {
        const availableWidth = container.offsetWidth;
        const actualWidth = container.scrollWidth;
        
        if (actualWidth > availableWidth && availableWidth > 0) {
            container.style.transform = `scale(${availableWidth / actualWidth})`;
        }
    });
}

// ============== 绑定事件监听 ==============

// 1. 页面窗口大小改变时，实时重新居中分配
window.addEventListener('resize', alignAndScaleMath);

// 2. 页面加载与 KaTeX 渲染完成后计算
document.addEventListener("DOMContentLoaded", alignAndScaleMath);
