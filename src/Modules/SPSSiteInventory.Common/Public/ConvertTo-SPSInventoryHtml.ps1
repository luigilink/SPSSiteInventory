function ConvertTo-SPSInventoryHtml {
    <#
        .SYNOPSIS
        Renders the scored inventory as a single self-contained HTML report.

        .DESCRIPTION
        ConvertTo-SPSInventoryHtml is a pure function (no SharePoint calls) so it can be
        unit tested without a farm. It takes the scored inventory records (as produced by
        the orchestrator: one PSCustomObject per site with identity, volumetry and the
        Category / CategoryName / Score / Reasons fields) and returns a complete HTML
        document as a single string.

        The output is entirely self-contained: all CSS and the small sort/filter script
        are inlined, so the file opens correctly from disk or a share with no external
        resource, CDN or font download. The house style uses the Aptos font family, blue
        headings (rgb(31, 56, 100)) and a summary box that breaks the estate down by
        migration-complexity category (1 Simple to 4 Blocking).

        Every field value is HTML-encoded, so URLs, titles and reasons cannot break the
        markup.

        .PARAMETER InputObject
        The scored inventory records to render. Each record is expected to expose Url,
        Title, WebApp, ContentDb, Template, SizeGB, SubWebCount, LastModified, Category,
        CategoryName, Score and Reasons. Missing fields are rendered empty.

        .PARAMETER EnvName
        Free-form environment identifier shown in the report header (for example 'PROD').

        .PARAMETER Title
        Report title. Defaults to 'SharePoint Site Inventory'.

        .PARAMETER GeneratedOn
        Timestamp shown in the header. Defaults to the current date and time. Exposed so
        callers (and tests) can produce a deterministic document.

        .EXAMPLE
        $html = ConvertTo-SPSInventoryHtml -InputObject $scored -EnvName 'PROD'
        Set-Content -Path report.html -Value $html -Encoding UTF8
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter()]
        [System.String]
        $EnvName = '',

        [Parameter()]
        [System.String]
        $Title = 'SharePoint Site Inventory',

        [Parameter()]
        [System.DateTime]
        $GeneratedOn = (Get-Date)
    )

    # Category metadata: name and accent colour for each complexity level. A plain
    # hashtable (not [ordered]) is used on purpose: an OrderedDictionary indexed by an
    # integer key resolves by position, not by key, which would mis-map the categories.
    # Order is enforced by iterating 1..4 explicitly.
    $categoryMeta = @{
        1 = @{ Name = 'Simple'; Color = '#107C10' }
        2 = @{ Name = 'Moderate'; Color = '#C19C00' }
        3 = @{ Name = 'Complex'; Color = '#D83B01' }
        4 = @{ Name = 'Blocking'; Color = '#A4262C' }
    }

    $records = @($InputObject)
    $total = $records.Count

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    # Per-category counts and total size.
    $counts = @{ 1 = 0; 2 = 0; 3 = 0; 4 = 0 }
    $totalSize = 0.0
    foreach ($record in $records) {
        $cat = 0
        if ($null -ne $record.Category) { $cat = [int]$record.Category }
        if ($counts.ContainsKey($cat)) { $counts[$cat]++ }

        if ($null -ne $record.SizeGB) {
            try { $totalSize += [double]$record.SizeGB }
            catch { Write-Verbose -Message "Ignoring non-numeric SizeGB '$($record.SizeGB)': $($_.Exception.Message)" }
        }
    }
    $totalSize = [math]::Round($totalSize, 2)

    $encTitle = ConvertTo-SPSHtmlText -Value $Title
    $encEnv = ConvertTo-SPSHtmlText -Value $EnvName
    $encGenerated = ConvertTo-SPSHtmlText -Value $GeneratedOn.ToString('yyyy-MM-dd HH:mm')

    $style = @'
<style>
:root {
    --brand: rgb(31, 56, 100);
    --brand-soft: rgb(31, 56, 100, 0.08);
    --border: #d9dce1;
    --text: #1f2328;
    --muted: #59636e;
    --cat1: #107C10;
    --cat2: #C19C00;
    --cat3: #D83B01;
    --cat4: #A4262C;
}
* { box-sizing: border-box; }
body {
    margin: 0;
    padding: 24px;
    font-family: 'Aptos', 'Segoe UI', system-ui, -apple-system, 'Helvetica Neue', Arial, sans-serif;
    color: var(--text);
    background: #f5f6f8;
    font-size: 14px;
    line-height: 1.45;
}
h1, h2, h3 { color: var(--brand); font-weight: 600; }
h1 { margin: 0 0 4px; font-size: 24px; }
h2 { margin: 28px 0 12px; font-size: 18px; }
.wrap { max-width: 1400px; margin: 0 auto; }
.header { border-bottom: 3px solid var(--brand); padding-bottom: 12px; margin-bottom: 8px; }
.meta { color: var(--muted); font-size: 13px; }
.meta strong { color: var(--text); }
.summary {
    border: 1px solid var(--border);
    border-left: 4px solid var(--brand);
    background: #fff;
    border-radius: 6px;
    padding: 16px 18px;
    margin: 16px 0 8px;
}
.summary-total { font-size: 15px; margin-bottom: 12px; }
.summary-total strong { color: var(--brand); font-size: 18px; }
.cards { display: flex; flex-wrap: wrap; gap: 12px; }
.card {
    flex: 1 1 160px;
    border: 1px solid var(--border);
    border-top: 4px solid var(--muted);
    border-radius: 6px;
    padding: 12px 14px;
    background: #fff;
}
.card .num { font-size: 26px; font-weight: 700; line-height: 1; }
.card .lbl { font-size: 13px; color: var(--muted); margin-top: 4px; }
.card .pct { font-size: 12px; color: var(--muted); }
.card.c1 { border-top-color: var(--cat1); } .card.c1 .num { color: var(--cat1); }
.card.c2 { border-top-color: var(--cat2); } .card.c2 .num { color: var(--cat2); }
.card.c3 { border-top-color: var(--cat3); } .card.c3 .num { color: var(--cat3); }
.card.c4 { border-top-color: var(--cat4); } .card.c4 .num { color: var(--cat4); }
.filters { margin: 8px 0 12px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.filters button {
    font: inherit;
    cursor: pointer;
    border: 1px solid var(--border);
    background: #fff;
    color: var(--text);
    padding: 5px 12px;
    border-radius: 999px;
}
.filters button.active { background: var(--brand); color: #fff; border-color: var(--brand); }
.table-scroll { overflow-x: auto; border: 1px solid var(--border); border-radius: 6px; background: #fff; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
thead th {
    position: sticky; top: 0;
    background: var(--brand); color: #fff;
    text-align: left; padding: 9px 10px; white-space: nowrap;
    cursor: pointer; user-select: none;
}
thead th .arrow { opacity: 0.6; font-size: 11px; }
tbody td { padding: 8px 10px; border-top: 1px solid var(--border); vertical-align: top; }
tbody tr:hover { background: var(--brand-soft); }
td.num, th.num { text-align: right; }
td.url { max-width: 320px; word-break: break-all; }
td.reasons { max-width: 340px; color: var(--muted); }
.badge {
    display: inline-block; padding: 2px 10px; border-radius: 999px;
    color: #fff; font-size: 12px; font-weight: 600; white-space: nowrap;
}
.b1 { background: var(--cat1); } .b2 { background: var(--cat2); }
.b3 { background: var(--cat3); } .b4 { background: var(--cat4); }
.footer { color: var(--muted); font-size: 12px; margin-top: 18px; text-align: center; }
</style>
'@

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine(('<title>{0}{1}</title>' -f $encTitle, $(if ($encEnv) { ' - ' + $encEnv } else { '' })))
    [void]$sb.AppendLine($style)
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('<div class="wrap">')

    # Header.
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine(('<h1>{0}</h1>' -f $encTitle))
    $envPart = if ($encEnv) { ('Environment <strong>{0}</strong> &middot; ' -f $encEnv) } else { '' }
    [void]$sb.AppendLine(('<div class="meta">{0}Generated on <strong>{1}</strong></div>' -f $envPart, $encGenerated))
    [void]$sb.AppendLine('</div>')

    # Summary box.
    [void]$sb.AppendLine('<div class="summary">')
    [void]$sb.AppendLine(('<div class="summary-total"><strong>{0}</strong> site collection(s) &middot; <strong>{1} GB</strong> total content</div>' -f $total, $totalSize.ToString($invariant)))
    [void]$sb.AppendLine('<div class="cards">')
    foreach ($key in 1..4) {
        $meta = $categoryMeta[$key]
        $count = $counts[[int]$key]
        $pct = if ($total -gt 0) { [math]::Round(($count / $total) * 100, 1) } else { 0 }
        [void]$sb.AppendLine(('<div class="card c{0}"><div class="num">{1}</div><div class="lbl">{0}. {2}</div><div class="pct">{3}%</div></div>' -f $key, $count, $meta.Name, $pct.ToString($invariant)))
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    # Filter bar.
    [void]$sb.AppendLine('<div class="filters">')
    [void]$sb.AppendLine('<button data-filter="all" class="active">All</button>')
    foreach ($key in 1..4) {
        [void]$sb.AppendLine(('<button data-filter="{0}">{1}. {2}</button>' -f $key, $key, $categoryMeta[$key].Name))
    }
    [void]$sb.AppendLine('</div>')

    # Table.
    $columns = @(
        @{ Key = 'Url'; Label = 'URL'; Class = 'url'; Type = 'text' }
        @{ Key = 'Title'; Label = 'Title'; Class = ''; Type = 'text' }
        @{ Key = 'WebApp'; Label = 'Web application'; Class = ''; Type = 'text' }
        @{ Key = 'ContentDb'; Label = 'Content DB'; Class = ''; Type = 'text' }
        @{ Key = 'Template'; Label = 'Template'; Class = ''; Type = 'text' }
        @{ Key = 'SizeGB'; Label = 'Size (GB)'; Class = 'num'; Type = 'num' }
        @{ Key = 'SubWebCount'; Label = 'Sub-webs'; Class = 'num'; Type = 'num' }
        @{ Key = 'LastModified'; Label = 'Last modified'; Class = ''; Type = 'text' }
        @{ Key = 'Score'; Label = 'Score'; Class = 'num'; Type = 'num' }
    )

    [void]$sb.AppendLine('<div class="table-scroll">')
    [void]$sb.AppendLine('<table id="inv">')
    [void]$sb.AppendLine('<thead><tr>')
    foreach ($col in $columns) {
        $thClass = if ($col.Class -eq 'num') { ' class="num"' } else { '' }
        [void]$sb.AppendLine(('<th{0} data-type="{1}">{2} <span class="arrow"></span></th>' -f $thClass, $col.Type, (ConvertTo-SPSHtmlText -Value $col.Label)))
    }
    [void]$sb.AppendLine('<th data-type="num">Category <span class="arrow"></span></th>')
    [void]$sb.AppendLine('<th data-type="text">Reasons <span class="arrow"></span></th>')
    [void]$sb.AppendLine('</tr></thead>')
    [void]$sb.AppendLine('<tbody>')

    foreach ($record in $records) {
        $cat = 0
        if ($null -ne $record.Category) { $cat = [int]$record.Category }
        $catName = if ($categoryMeta.Contains($cat)) { $categoryMeta[$cat].Name } elseif ($record.CategoryName) { [string]$record.CategoryName } else { '' }

        [void]$sb.AppendLine(('<tr data-category="{0}">' -f $cat))
        foreach ($col in $columns) {
            $raw = $record.$($col.Key)
            if ($col.Key -eq 'LastModified' -and $raw -is [datetime]) {
                $raw = $raw.ToString('yyyy-MM-dd')
            }
            elseif ($col.Type -eq 'num' -and ($raw -is [double] -or $raw -is [single] -or $raw -is [decimal] -or $raw -is [int] -or $raw -is [long])) {
                $raw = ([System.IConvertible]$raw).ToString($invariant)
            }
            $tdClass = if ($col.Class) { (' class="{0}"' -f $col.Class) } else { '' }
            [void]$sb.AppendLine(('<td{0}>{1}</td>' -f $tdClass, (ConvertTo-SPSHtmlText -Value $raw)))
        }
        [void]$sb.AppendLine(('<td data-sort="{0}"><span class="badge b{0}">{1}</span></td>' -f $cat, (ConvertTo-SPSHtmlText -Value $catName)))
        [void]$sb.AppendLine(('<td class="reasons">{0}</td>' -f (ConvertTo-SPSHtmlText -Value $record.Reasons)))
        [void]$sb.AppendLine('</tr>')
    }

    [void]$sb.AppendLine('</tbody>')
    [void]$sb.AppendLine('</table>')
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<div class="footer">Generated by SPSSiteInventory &middot; read-only inventory &middot; no farm changes</div>')
    [void]$sb.AppendLine('</div>')

    $script = @'
<script>
(function () {
    var table = document.getElementById('inv');
    if (!table) { return; }
    var tbody = table.tBodies[0];

    function cellSortValue(row, index, type) {
        var cell = row.cells[index];
        var raw = cell.getAttribute('data-sort');
        if (raw === null) { raw = cell.textContent.trim(); }
        if (type === 'num') {
            var n = parseFloat(raw);
            return isNaN(n) ? -Infinity : n;
        }
        return raw.toLowerCase();
    }

    var headers = table.tHead.rows[0].cells;
    for (var i = 0; i < headers.length; i++) {
        (function (index) {
            var th = headers[index];
            var type = th.getAttribute('data-type') || 'text';
            th.addEventListener('click', function () {
                var asc = th.getAttribute('data-dir') !== 'asc';
                for (var h = 0; h < headers.length; h++) {
                    headers[h].removeAttribute('data-dir');
                    var a = headers[h].querySelector('.arrow');
                    if (a) { a.textContent = ''; }
                }
                th.setAttribute('data-dir', asc ? 'asc' : 'desc');
                var arrow = th.querySelector('.arrow');
                if (arrow) { arrow.textContent = asc ? '\u25B2' : '\u25BC'; }

                var rows = Array.prototype.slice.call(tbody.rows);
                rows.sort(function (r1, r2) {
                    var v1 = cellSortValue(r1, index, type);
                    var v2 = cellSortValue(r2, index, type);
                    if (v1 < v2) { return asc ? -1 : 1; }
                    if (v1 > v2) { return asc ? 1 : -1; }
                    return 0;
                });
                for (var r = 0; r < rows.length; r++) { tbody.appendChild(rows[r]); }
            });
        })(i);
    }

    var buttons = document.querySelectorAll('.filters button');
    for (var b = 0; b < buttons.length; b++) {
        buttons[b].addEventListener('click', function () {
            var filter = this.getAttribute('data-filter');
            for (var k = 0; k < buttons.length; k++) { buttons[k].classList.remove('active'); }
            this.classList.add('active');
            var rows = tbody.rows;
            for (var r = 0; r < rows.length; r++) {
                var cat = rows[r].getAttribute('data-category');
                rows[r].style.display = (filter === 'all' || filter === cat) ? '' : 'none';
            }
        });
    }
})();
</script>
'@
    [void]$sb.AppendLine($script)
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    return $sb.ToString()
}
