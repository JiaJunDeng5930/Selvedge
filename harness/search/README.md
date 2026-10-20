# Conversation history search

Searches committed user and assistant text across Tasks, including speech
transcripts. It reads original history positions without introducing persisted
search state. Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend),
and [PROOF.bend](PROOF.bend). The public `search_history` command and native agent
tool both reach this implementation through `Commands.query`.
