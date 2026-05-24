import type { ReactNode } from "react";

interface EmptyStateProps {
	icon: ReactNode;
	title: string;
	description: ReactNode;
	action?: ReactNode;
}

export const EmptyState: React.FC<EmptyStateProps> = ({
	icon,
	title,
	description,
	action,
}) => {
	return (
		<div className="empty-state">
			<div className="empty-state-icon">{icon}</div>
			<div className="empty-state-title">{title}</div>
			<div className="empty-state-desc">{description}</div>
			{action && <div className="empty-state-action">{action}</div>}
		</div>
	);
};
