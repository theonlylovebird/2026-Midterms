command: """
/usr/bin/curl -s 'https://api.elections.kalshi.com/trade-api/v2/markets/CONTROLH-2026-D' | /usr/bin/python3 -c "import sys,json; m=json.load(sys.stdin).get('market',{}); print('CONTROLH='+str(m.get('yes_bid_dollars','0')))"
/usr/bin/curl -s 'https://api.elections.kalshi.com/trade-api/v2/markets/CONTROLS-2026-D' | /usr/bin/python3 -c "import sys,json; m=json.load(sys.stdin).get('market',{}); print('CONTROLS='+str(m.get('yes_bid_dollars','0')))"
/usr/bin/curl -s 'https://api.elections.kalshi.com/trade-api/v2/markets/SENATETX-26-D' | /usr/bin/python3 -c "import sys,json; m=json.load(sys.stdin).get('market',{}); print('SENATETX='+str(m.get('yes_bid_dollars','0')))"
"""

refreshFrequency: 300000

render: (output) ->
  kalshi = {}
  for line in (output or "").trim().split("\n")
    if "=" not in line then continue
    [key, val] = line.split("=")
    demPct = Math.round(parseFloat(val) * 100)
    if isNaN(demPct) then continue
    if key is "CONTROLH"
      kalshi["House winner"] = if demPct >= 50 then { name: "Democratic Party", party: "dem", pct: demPct } else { name: "Republican Party", party: "rep", pct: 100 - demPct }
    if key is "CONTROLS"
      kalshi["Senate winner"] = if demPct >= 50 then { name: "Democratic Party", party: "dem", pct: demPct } else { name: "Republican Party", party: "rep", pct: 100 - demPct }
    if key is "SENATETX"
      kalshi["Texas Senate"] = if demPct >= 50 then { name: "Democratic Party", party: "dem", pct: demPct } else { name: "Republican Party", party: "rep", pct: 100 - demPct }

  window._kalshiRows = kalshi

  """
  <div id="pm-widget">
    <div class="pm-header">
      <span class="pm-title">2026 Midterms</span>
    </div>
    <div id="pm-markets">
      <div class="pm-loading">Loading...</div>
    </div>
    <div id="pm-updated"></div>
  </div>
  """

afterRender: (domEl) ->
  polySlugs = [
    "which-party-will-win-the-house-in-2026"
    "which-party-will-win-the-senate-in-2026"
    "texas-senate-election-winner"
  ]
  labels = ["House winner", "Senate winner", "Texas Senate"]

  extractParty = (question) ->
    if /democratic party|democrats? win|democrats? control/i.test(question)
      return { name: "Democratic Party", party: "dem" }
    if /republican party|republicans? win|republicans? control/i.test(question)
      return { name: "Republican Party", party: "rep" }
    if /democrat/i.test(question) then return { name: "Democrat", party: "dem" }
    if /republican/i.test(question) then return { name: "Republican", party: "rep" }
    null

  renderRow = (label, name, party, pct, source) ->
    lbl = if label then "<div class='pm-question'>#{label}</div>" else ""
    """
    <div class="pm-row">
      #{lbl}
      <div class="pm-result">
        <span class="pm-candidate #{party}">#{name}</span>
        <span class="pm-pct">#{pct}%</span>
        <span class="pm-tag #{source}">#{source}</span>
      </div>
      <div class="pm-bar-bg">
        <div class="pm-bar #{party}" style="width:#{pct}%"></div>
      </div>
    </div>
    """

  promises = polySlugs.map((slug) ->
    fetch("http://127.0.0.1:41417/gamma-api.polymarket.com/events?slug=#{slug}")
      .then((r) -> r.json()).catch(-> [])
  )

  Promise.all(promises).then((results) ->
    container = domEl.querySelector("#pm-markets")
    updated   = domEl.querySelector("#pm-updated")
    kalshi    = window._kalshiRows or {}
    html = ""

    for result, idx in results
      try
        events = if Array.isArray(result) then result else [result]
        event  = events[0]
        if not event then continue
        chosen = null; chosenPct = null; chosenParty = null
        for m in (event.markets or [])
          outcomes = if typeof m.outcomes is 'string' then JSON.parse(m.outcomes) else (m.outcomes or [])
          prices   = if typeof m.outcomePrices is 'string' then JSON.parse(m.outcomePrices) else (m.outcomePrices or [])
          isYesNo  = outcomes.every((o) -> /^(yes|no)$/i.test(o.trim()))
          if isYesNo
            yi = outcomes.findIndex((o) -> /^yes$/i.test(o.trim()))
            if yi >= 0
              yp = parseFloat(prices[yi] or 0)
              p  = extractParty(m.question or "")
              if p and yp > 0.5 and (not chosen or yp > chosenPct)
                chosen = p.name; chosenPct = yp; chosenParty = p.party
          else
            lead = outcomes[0]; lp = parseFloat(prices[0] or 0)
            for i in [1...outcomes.length]
              v = parseFloat(prices[i] or 0)
              if v > lp then lp = v; lead = outcomes[i]
            isDem = /democrat|democratic/i.test(lead)
            isRep = /republican/i.test(lead)
            if isDem or isRep
              chosen = lead; chosenPct = lp
              chosenParty = if isDem then "dem" else "rep"
              break

        label = labels[idx]
        kd    = kalshi[label]
        if chosen
          html += renderRow(label, chosen, chosenParty, Math.round(chosenPct * 100), "poly")
        if kd
          html += renderRow((if chosen then "" else label), kd.name, kd.party, kd.pct, "kalshi")
        html += '<div class="pm-divider"></div>'
      catch e then continue

    container.innerHTML = if html then html else '<div class="pm-loading">No data</div>'
    now = new Date()
    updated.textContent = "Updated #{now.toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}"
  ).catch(->
    domEl.querySelector("#pm-markets").innerHTML = '<div class="pm-loading">Failed to load</div>'
  )

style: """
  left: 20px
  top: 20px
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif

  #pm-widget
    width: 300px
    background: rgba(15, 15, 20, 0.82)
    backdrop-filter: blur(20px)
    -webkit-backdrop-filter: blur(20px)
    border-radius: 14px
    border: 0.5px solid rgba(255,255,255,0.12)
    padding: 16px 18px 14px
    color: #fff

  .pm-header
    display: flex
    justify-content: space-between
    align-items: baseline
    margin-bottom: 14px

  .pm-title
    font-size: 14px
    font-weight: 600
    letter-spacing: 0.05em
    color: rgba(255,255,255,0.9)
    text-transform: uppercase

  .pm-loading
    font-size: 12px
    color: rgba(255,255,255,0.4)
    padding: 8px 0

  .pm-divider
    height: 0.5px
    background: rgba(255,255,255,0.07)
    margin: 6px 0 8px

  .pm-row
    margin-bottom: 4px

  .pm-question
    font-size: 11px
    color: rgba(255,255,255,0.45)
    margin-bottom: 3px

  .pm-result
    display: flex
    align-items: baseline
    gap: 6px
    margin-bottom: 3px

  .pm-candidate
    font-size: 13px
    font-weight: 500
    flex: 1

  .pm-candidate.dem
    color: #5b9cf6

  .pm-candidate.rep
    color: #f27060

  .pm-pct
    font-size: 14px
    font-weight: 600
    color: rgba(255,255,255,0.9)

  .pm-tag
    font-size: 9px
    font-weight: 500
    letter-spacing: 0.05em
    padding: 2px 5px
    border-radius: 4px
    text-transform: uppercase
    min-width: 38px
    text-align: center

  .pm-tag.poly
    background: rgba(255,255,255,0.07)
    color: rgba(255,255,255,0.3)

  .pm-tag.kalshi
    background: rgba(91,156,246,0.15)
    color: rgba(91,156,246,0.65)

  .pm-bar-bg
    height: 2px
    background: rgba(255,255,255,0.07)
    border-radius: 2px
    overflow: hidden
    margin-bottom: 1px

  .pm-bar
    height: 100%
    border-radius: 2px

  .pm-bar.dem
    background: #5b9cf6

  .pm-bar.rep
    background: #f27060

  #pm-updated
    font-size: 10px
    color: rgba(255,255,255,0.22)
    margin-top: 10px
    text-align: right
"""
