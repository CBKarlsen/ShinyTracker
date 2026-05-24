import React from "react";

interface ErrorBannerProps {
	message: string;
	onDismiss: () => void;
}

export const ErrorBanner: React.FC<ErrorBannerProps> = ({
	message,
	onDismiss,
}) => {
	if (!message) return null;
	
	return (
		<div className="error-banner">
			<div className="error-banner-content">
				<span className="error-banner-message">{message}</span>
				<button className="error-banner-dismiss" onClick={onDismiss}>
					dismiss
				</button>
			</div>
		</div>
	);
};
