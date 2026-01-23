// 1. Setup
const startPage = dv.current().file.path;
const directRows = [];
const indirectRows = [];
const visited = new Set();

// 2. Recursive Crawler
async function crawl(pagePath, depth = 0) {
    if (visited.has(pagePath)) return;
    visited.add(pagePath);
    
    const page = dv.page(pagePath);
    if (!page) return;

    // Filter: Ignore the starting page itself
    if (page.file.path !== startPage) {
        // Collect data: [Link, Type]
        const data = [page.file.link, page.type || "N/A"];
        
        if (depth === 1) {
            directRows.push(data);
        } else if (depth > 1) {
            indirectRows.push(data);
        }
    }

    // Follow the 'down' property
    const children = dv.array(page.down);
    for (const child of children) {
        if (child?.path) {
            await crawl(child.path, depth + 1);
        }
    }
}

// 3. Execution & Sorting
await crawl(startPage);

// Helper function to sort by 'Type' (index 1 of the array)
const sortByType = (a, b) => (a[1] || "").localeCompare(b[1] || "");

// 4. Render Tables
dv.header(3, "Direct Dependencies");
if (directRows.length > 0) {
    dv.table(["File", "Type"], directRows.sort(sortByType));
} else {
    dv.paragraph("No direct dependencies found.");
}

dv.header(3, "Indirect Dependencies");
if (indirectRows.length > 0) {
    dv.table(["File", "Type"], indirectRows.sort(sortByType));
} else {
    dv.paragraph("No indirect dependencies found.");
}
