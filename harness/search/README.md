# Conversation history search

Searches committed user and assistant text across Tasks, including speech
transcripts and provider assistant messages displayed as conversation speech.
Provider speech uses the conversation decoder, including provider receipts;
reasoning, compaction and tool records stay outside the text search.
It reads original history positions without introducing persisted
search state. Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend),
and [PROOF.bend](PROOF.bend). The public `search_history` command and native agent
tool both reach this implementation through `Commands.query`.
