# Nansen: on-chain pipeline design

## 1. Introduction: (the "what")

### 1.1 Labelling

On-chain address labeling is a pretty open topic, with many companies and participants taking part in it with different approaches. We could summarize labelling as:

> *The process of adding a qualitative descriptor that provides information regarding the behavior, nature or origin of an address or address operator. We could extend this for other kinds of labels (like soft scores or quantiles) that are, in a similar fashion, summarized information tagging the address in question.*

It's important to take into account that a correct approach towards labelling should consider that:
- Labels are **timely**, e.g. they are aligned with a snapshot in time, dynamic, and mutable (we will talk about this in the data modeling part), there is a time dimension that needs to be part of our data model and our grain decision/s.
- Labels are **actionable**, they should be able to add information to act uppon.
- They should be **trustworthy**, either inferred from on-chain info or (in some cases) from external sources with high confidence.

The concept of labelling really is an open-ended problem. From a customer centric, bottom up approach, we need to understand who our customers & users are to derive what a valuable label means. Labels answer questions like:

- ***WHO is this entity?:*** exchanges, treasuries, protocol builders, whales, market makers, smart contracts (which may have automated behavior built in so are worth tracking, etc).
- ***WHAT does this entity do?:*** are they liquidity providers, speculators, MEV-like bots, smart contract / factory deployers, stakers, staking aggregators, routers, etc.
- ***WHY should users care?:*** e.g. what makes these addresses valuable for our users?

The reason why the bottom up approach is important is because our users directly dictate the value of a label. Imagine we are a staking infra provider who wants to operate for big funds, exchanges or entities (banks) to provide the staking infrastructure as a service. We really only care about these labels (not so much about smart traders or spoofers) since we use the labels as a sales tool to try to get customers.

*In the case of Nansen, where users will mainly be looking for:*
- Alpha: finding statistically significant sources of information that are not fully priced in and can provide risk adjusted returns that are better than holding a *traditional* weighted average portfolio.
- Beta: some users will be looking for sources of increased beta exposure (pump or vol), e.g. finding the next move of assets (or a subclass of assets like small cap tokens) that will, in case of a run, provide increased beta exposure. In other cases, users may want to do the opposite, find assets with positive alpha and low to zero beta (low correlation to the index or BTC).
- Sigma: raw exposure or hedging against future volatility moves.
These requirements should shape the kind of information we want our labels to provide.

### 1.2 A generic data pipeline / platform system design recipe

[TODO]

## 2. Approaches to on-chain address labeling (the "how")

This section will discuss different approaches (and just ideas that should be validated) to on-chain labelling that could be valuable to users looking for sources of alpha, risk mitigation or market neutrality.

### 2.1 Entity labels from external sources

Some entity-label providers like Glassnode, Arkham or Dune compile information from different web2 sources (reports, websites, information providers, API aggregators, etc) which may tag addresses as exchanges, fund treasuries, node operators, protocols/contract deployers, etc. They may also run sophisticated graph algorithms (for instance Glassnode does this for UTXO chains like BTC or BTC cash) or heuristics on EVMs to add soft labels to new addresses quicker than anyone else. These may be useful for users to track what big players or the overall market is doing (*are whales inactive? Are long term holders moving funds to exchanges? What are big funds' recent movements? How are staking operators' treasuries handling liquidity?*).

> *These are usually simple `ELT | poll -> normalize -> transform` pipelines. Poll from APIs (or listen to socket streams), parse, ingest and store. Then a classic layered data model will have an initial lower grain layer (bronze) where we just normalize different inputs to our desired schema, ensure id-grain level uniqueness and normally follow a slow-changing-dimension approach where we process our event timestamps to add a time grain and validity to labels (`timestamp_from`, `timestamp_to`, etc). For graph algorithms we may have more complex distributed jobs that come after our initial semantic layer, with heuristics written in plain `pySpark` or similar, but these are still linear pipelines.*

### 2.2 Behavioral & descriptive labels in EVMs (or similar)

EVMs (or similar chains) provide in depth information of a certain address's behavior in terms of:
- ***Native VM balances, token balances, token transfers, etc:*** these can provide information worth labelling like player size per token (whales, etc), long term holders (cohorts), active/inactive addresses (by number of transfers), etc.
- ***Interaction of an address with smart contracts; logs, traces, etc:*** with which we can know information such as: players providing liquidity in DEX pools (plus their impermanent loss or MTM), their positioning (are these providing buy side liquidity, e.g. are they providing *support* to the price, are they bull or bear LPs), their floating PnL (which could be predictive of future stops), or more advanced stuff like if they are providing double sided liquidity, are diversified and highly active (typical patterns of market makers). Other addresses may be deploying smart contracts, interacting with staking protocols (big stakers, fixed income crypto providers, etc), big lenders and others. These could also be interesting as their behavior does lead or lag price movements, just because of their sheer size of interaction with smart contracts..3

> *In terms of system design and typical patterns for these kind of pipelines, we will discuss this further down the line as the first sample pipeline describes this in section ***3.1***; the approach towards these really depends on our requirements, a mini-batch near real-time pipeline can be quite simple, the 

### 2.3 Behavioral & descriptive labels in CLOB chains (or similar)

CLOB chains (like HyperLiquid's HyperCore or Jupiter) provide deep information regarding the interaction of addresses with the chain's central limit order books. 

### 2.4 Smart Money (both EVM or CLOB): an alternative approach

[ TODO ]

## 3. Pipeline sample #1: an EVM smart trader
