from django.conf.urls import patterns, url
from comment import views

urlpatterns = patterns('comment.views',
    url(r'^$', 'home'),
	url(r'add$', views.add_comment, name='add_comment'),
)