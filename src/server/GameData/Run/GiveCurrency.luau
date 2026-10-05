--!strict

-- Give Currency (M32): a prompt on every other player opens a menu that
-- sends them Gold Bars and Iron Bars from the sender's own balances.
return {
	-- how much one press of plus or minus changes an amount; holding the
	-- button repeats it, faster and faster (the menu's own timing)
	STEP = 1,
	PROMPT_ACTION_TEXT = "Give Currency",
	PROMPT_MAX_DISTANCE_STUDS = 8,

	-- "[DisplayName] sent you [amounts]" to the receiver
	RECEIVED_FORMAT = "%s sent you %s",
	-- "You sent [amounts] to [DisplayName]" to the sender
	SENT_FORMAT = "You sent %s to %s",
	NOTHING_FEEDBACK = "Choose an amount to send",
	BALANCE_FEEDBACK = "You do not have that much",
	UNAVAILABLE_FEEDBACK = "That player cannot receive currency right now",
	FEEDBACK_DISPLAY_SEC = 5,
}
