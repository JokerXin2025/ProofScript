document.addEventListener("DOMContentLoaded", function() {
    renderMathInElement(document.body, {
        delimiters: [
            {left: '$$', right: '$$', display: true},
            {left: '$', right: '$', display: false},
        ],
        ignoredClasses: ['proof-text-literal'],
        trust: function(context) {
            return context.command === '\\htmlData';
        },
    });
});
